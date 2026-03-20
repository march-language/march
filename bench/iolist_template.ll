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

@.str1 = private unnamed_addr constant [1 x i8] c"\00"
@.str2 = private unnamed_addr constant [9 x i8] c"<tr><td>\00"
@.str3 = private unnamed_addr constant [10 x i8] c"</td><td>\00"
@.str4 = private unnamed_addr constant [12 x i8] c"</td></tr>\0A\00"

define ptr @IOList.from_string(ptr %s.arg) {
entry:
  %s.addr = alloca ptr
  store ptr %s.arg, ptr %s.addr
  %ld1 = load ptr, ptr %s.addr
  call void @march_incrc(ptr %ld1)
  %ld2 = load ptr, ptr %s.addr
  %cr3 = call i64 @march_string_is_empty(ptr %ld2)
  %$t186.addr = alloca i64
  store i64 %cr3, ptr %$t186.addr
  %ld4 = load i64, ptr %$t186.addr
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
  %hp8 = call ptr @march_alloc(i64 24)
  %tgp9 = getelementptr i8, ptr %hp8, i64 8
  store i32 1, ptr %tgp9, align 4
  %ld10 = load ptr, ptr %s.addr
  %fp11 = getelementptr i8, ptr %hp8, i64 16
  store ptr %ld10, ptr %fp11, align 8
  store ptr %hp8, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r12 = load ptr, ptr %res_slot5
  ret ptr %case_r12
}

define ptr @IOList.append(ptr %a.arg, ptr %b.arg) {
entry:
  %a.addr = alloca ptr
  store ptr %a.arg, ptr %a.addr
  %b.addr = alloca ptr
  store ptr %b.arg, ptr %b.addr
  %ld13 = load ptr, ptr %a.addr
  call void @march_incrc(ptr %ld13)
  %ld14 = load ptr, ptr %b.addr
  call void @march_incrc(ptr %ld14)
  %hp15 = call ptr @march_alloc(i64 32)
  %tgp16 = getelementptr i8, ptr %hp15, i64 8
  store i32 0, ptr %tgp16, align 4
  %ld17 = load ptr, ptr %a.addr
  %fp18 = getelementptr i8, ptr %hp15, i64 16
  store ptr %ld17, ptr %fp18, align 8
  %ld19 = load ptr, ptr %b.addr
  %fp20 = getelementptr i8, ptr %hp15, i64 24
  store ptr %ld19, ptr %fp20, align 8
  %$t187.addr = alloca ptr
  store ptr %hp15, ptr %$t187.addr
  %ld21 = load ptr, ptr %$t187.addr
  %res_slot22 = alloca ptr
  %tgp23 = getelementptr i8, ptr %ld21, i64 8
  %tag24 = load i32, ptr %tgp23, align 4
  switch i32 %tag24, label %case_default5 [
      
  ]
case_default5:
  %hp25 = call ptr @march_alloc(i64 16)
  %tgp26 = getelementptr i8, ptr %hp25, i64 8
  store i32 0, ptr %tgp26, align 4
  %$t188.addr = alloca ptr
  store ptr %hp25, ptr %$t188.addr
  %hp27 = call ptr @march_alloc(i64 32)
  %tgp28 = getelementptr i8, ptr %hp27, i64 8
  store i32 1, ptr %tgp28, align 4
  %ld29 = load ptr, ptr %b.addr
  %fp30 = getelementptr i8, ptr %hp27, i64 16
  store ptr %ld29, ptr %fp30, align 8
  %ld31 = load ptr, ptr %$t188.addr
  %fp32 = getelementptr i8, ptr %hp27, i64 24
  store ptr %ld31, ptr %fp32, align 8
  %$t189.addr = alloca ptr
  store ptr %hp27, ptr %$t189.addr
  %hp33 = call ptr @march_alloc(i64 32)
  %tgp34 = getelementptr i8, ptr %hp33, i64 8
  store i32 1, ptr %tgp34, align 4
  %ld35 = load ptr, ptr %a.addr
  %fp36 = getelementptr i8, ptr %hp33, i64 16
  store ptr %ld35, ptr %fp36, align 8
  %ld37 = load ptr, ptr %$t189.addr
  %fp38 = getelementptr i8, ptr %hp33, i64 24
  store ptr %ld37, ptr %fp38, align 8
  %$t190.addr = alloca ptr
  store ptr %hp33, ptr %$t190.addr
  %hp39 = call ptr @march_alloc(i64 24)
  %tgp40 = getelementptr i8, ptr %hp39, i64 8
  store i32 2, ptr %tgp40, align 4
  %ld41 = load ptr, ptr %$t190.addr
  %fp42 = getelementptr i8, ptr %hp39, i64 16
  store ptr %ld41, ptr %fp42, align 8
  store ptr %hp39, ptr %res_slot22
  br label %case_merge4
case_merge4:
  %case_r43 = load ptr, ptr %res_slot22
  ret ptr %case_r43
}

define ptr @IOList.to_string(ptr %iol.arg) {
entry:
  %iol.addr = alloca ptr
  store ptr %iol.arg, ptr %iol.addr
  %hp44 = call ptr @march_alloc(i64 24)
  %tgp45 = getelementptr i8, ptr %hp44, i64 8
  store i32 0, ptr %tgp45, align 4
  %fp46 = getelementptr i8, ptr %hp44, i64 16
  store ptr @list_append$apply, ptr %fp46, align 8
  %list_append.addr = alloca ptr
  store ptr %hp44, ptr %list_append.addr
  %hp47 = call ptr @march_alloc(i64 32)
  %tgp48 = getelementptr i8, ptr %hp47, i64 8
  store i32 0, ptr %tgp48, align 4
  %fp49 = getelementptr i8, ptr %hp47, i64 16
  store ptr @collect_list$apply, ptr %fp49, align 8
  %ld50 = load ptr, ptr %list_append.addr
  %fp51 = getelementptr i8, ptr %hp47, i64 24
  store ptr %ld50, ptr %fp51, align 8
  %collect_list.addr = alloca ptr
  store ptr %hp47, ptr %collect_list.addr
  %hp52 = call ptr @march_alloc(i64 32)
  %tgp53 = getelementptr i8, ptr %hp52, i64 8
  store i32 0, ptr %tgp53, align 4
  %fp54 = getelementptr i8, ptr %hp52, i64 16
  store ptr @collect$apply, ptr %fp54, align 8
  %ld55 = load ptr, ptr %collect_list.addr
  %fp56 = getelementptr i8, ptr %hp52, i64 24
  store ptr %ld55, ptr %fp56, align 8
  %collect.addr = alloca ptr
  store ptr %hp52, ptr %collect.addr
  %ld57 = load ptr, ptr %collect.addr
  %fp58 = getelementptr i8, ptr %ld57, i64 16
  %fv59 = load ptr, ptr %fp58, align 8
  %ld60 = load ptr, ptr %iol.addr
  %cr61 = call ptr (ptr, ptr) %fv59(ptr %ld57, ptr %ld60)
  %$t200.addr = alloca ptr
  store ptr %cr61, ptr %$t200.addr
  %ld62 = load ptr, ptr %$t200.addr
  %sl63 = call ptr @march_string_lit(ptr @.str1, i64 0)
  %cr64 = call ptr @march_string_join(ptr %ld62, ptr %sl63)
  ret ptr %cr64
}

define ptr @render_row(i64 %i.arg) {
entry:
  %i.addr = alloca i64
  store i64 %i.arg, ptr %i.addr
  %sl65 = call ptr @march_string_lit(ptr @.str2, i64 8)
  %cr66 = call ptr @IOList.from_string(ptr %sl65)
  %iol.addr = alloca ptr
  store ptr %cr66, ptr %iol.addr
  %ld67 = load i64, ptr %i.addr
  %cr68 = call ptr @march_int_to_string(i64 %ld67)
  %$t351.addr = alloca ptr
  store ptr %cr68, ptr %$t351.addr
  %ld69 = load ptr, ptr %iol.addr
  %iol_i10.addr = alloca ptr
  store ptr %ld69, ptr %iol_i10.addr
  %ld70 = load ptr, ptr %$t351.addr
  %s_i11.addr = alloca ptr
  store ptr %ld70, ptr %s_i11.addr
  %ld71 = load ptr, ptr %s_i11.addr
  %cr72 = call ptr @IOList.from_string(ptr %ld71)
  %$t192_i12.addr = alloca ptr
  store ptr %cr72, ptr %$t192_i12.addr
  %ld73 = load ptr, ptr %iol_i10.addr
  %ld74 = load ptr, ptr %$t192_i12.addr
  %cr75 = call ptr @IOList.append(ptr %ld73, ptr %ld74)
  %iol_1.addr = alloca ptr
  store ptr %cr75, ptr %iol_1.addr
  %ld76 = load ptr, ptr %iol_1.addr
  %iol_i7.addr = alloca ptr
  store ptr %ld76, ptr %iol_i7.addr
  %sl77 = call ptr @march_string_lit(ptr @.str3, i64 9)
  %s_i8.addr = alloca ptr
  store ptr %sl77, ptr %s_i8.addr
  %ld78 = load ptr, ptr %s_i8.addr
  %cr79 = call ptr @IOList.from_string(ptr %ld78)
  %$t192_i9.addr = alloca ptr
  store ptr %cr79, ptr %$t192_i9.addr
  %ld80 = load ptr, ptr %iol_i7.addr
  %ld81 = load ptr, ptr %$t192_i9.addr
  %cr82 = call ptr @IOList.append(ptr %ld80, ptr %ld81)
  %iol_2.addr = alloca ptr
  store ptr %cr82, ptr %iol_2.addr
  %ld83 = load i64, ptr %i.addr
  %ld84 = load i64, ptr %i.addr
  %ar85 = mul i64 %ld83, %ld84
  %$t352.addr = alloca i64
  store i64 %ar85, ptr %$t352.addr
  %ld86 = load i64, ptr %$t352.addr
  %cr87 = call ptr @march_int_to_string(i64 %ld86)
  %$t353.addr = alloca ptr
  store ptr %cr87, ptr %$t353.addr
  %ld88 = load ptr, ptr %iol_2.addr
  %iol_i4.addr = alloca ptr
  store ptr %ld88, ptr %iol_i4.addr
  %ld89 = load ptr, ptr %$t353.addr
  %s_i5.addr = alloca ptr
  store ptr %ld89, ptr %s_i5.addr
  %ld90 = load ptr, ptr %s_i5.addr
  %cr91 = call ptr @IOList.from_string(ptr %ld90)
  %$t192_i6.addr = alloca ptr
  store ptr %cr91, ptr %$t192_i6.addr
  %ld92 = load ptr, ptr %iol_i4.addr
  %ld93 = load ptr, ptr %$t192_i6.addr
  %cr94 = call ptr @IOList.append(ptr %ld92, ptr %ld93)
  %iol_3.addr = alloca ptr
  store ptr %cr94, ptr %iol_3.addr
  %ld95 = load ptr, ptr %iol_3.addr
  %iol_i1.addr = alloca ptr
  store ptr %ld95, ptr %iol_i1.addr
  %sl96 = call ptr @march_string_lit(ptr @.str4, i64 11)
  %s_i2.addr = alloca ptr
  store ptr %sl96, ptr %s_i2.addr
  %ld97 = load ptr, ptr %s_i2.addr
  %cr98 = call ptr @IOList.from_string(ptr %ld97)
  %$t192_i3.addr = alloca ptr
  store ptr %cr98, ptr %$t192_i3.addr
  %ld99 = load ptr, ptr %iol_i1.addr
  %ld100 = load ptr, ptr %$t192_i3.addr
  %cr101 = call ptr @IOList.append(ptr %ld99, ptr %ld100)
  ret ptr %cr101
}

define ptr @build_rows(i64 %n.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld102 = load i64, ptr %n.addr
  %cmp103 = icmp eq i64 %ld102, 0
  %ar104 = zext i1 %cmp103 to i64
  %$t354.addr = alloca i64
  store i64 %ar104, ptr %$t354.addr
  %ld105 = load i64, ptr %$t354.addr
  %res_slot106 = alloca ptr
  switch i64 %ld105, label %case_default7 [
      i64 1, label %case_br8
  ]
case_br8:
  %ld107 = load ptr, ptr %acc.addr
  store ptr %ld107, ptr %res_slot106
  br label %case_merge6
case_default7:
  %ld108 = load i64, ptr %n.addr
  %ar109 = sub i64 %ld108, 1
  %$t355.addr = alloca i64
  store i64 %ar109, ptr %$t355.addr
  %ld110 = load i64, ptr %n.addr
  %cr111 = call ptr @render_row(i64 %ld110)
  %$t356.addr = alloca ptr
  store ptr %cr111, ptr %$t356.addr
  %ld112 = load ptr, ptr %acc.addr
  %ld113 = load ptr, ptr %$t356.addr
  %cr114 = call ptr @IOList.append(ptr %ld112, ptr %ld113)
  %$t357.addr = alloca ptr
  store ptr %cr114, ptr %$t357.addr
  %ld115 = load i64, ptr %$t355.addr
  %ld116 = load ptr, ptr %$t357.addr
  %cr117 = call ptr @build_rows(i64 %ld115, ptr %ld116)
  store ptr %cr117, ptr %res_slot106
  br label %case_merge6
case_merge6:
  %case_r118 = load ptr, ptr %res_slot106
  ret ptr %case_r118
}

define void @march_main() {
entry:
  %hp119 = call ptr @march_alloc(i64 16)
  %tgp120 = getelementptr i8, ptr %hp119, i64 8
  store i32 0, ptr %tgp120, align 4
  %$t358.addr = alloca ptr
  store ptr %hp119, ptr %$t358.addr
  %ld121 = load ptr, ptr %$t358.addr
  %cr122 = call ptr @build_rows(i64 50000, ptr %ld121)
  %table.addr = alloca ptr
  store ptr %cr122, ptr %table.addr
  %ld123 = load ptr, ptr %table.addr
  %cr124 = call ptr @IOList.to_string(ptr %ld123)
  %s.addr = alloca ptr
  store ptr %cr124, ptr %s.addr
  %ld125 = load ptr, ptr %s.addr
  %cr126 = call i64 @march_string_byte_length(ptr %ld125)
  %$t359.addr = alloca i64
  store i64 %cr126, ptr %$t359.addr
  %ld127 = load i64, ptr %$t359.addr
  %cr128 = call ptr @march_int_to_string(i64 %ld127)
  %$t360.addr = alloca ptr
  store ptr %cr128, ptr %$t360.addr
  %ld129 = load ptr, ptr %$t360.addr
  call void @march_println(ptr %ld129)
  ret void
}

define ptr @list_append$apply(ptr %$clo.arg, ptr %a.arg, ptr %b.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %a.addr = alloca ptr
  store ptr %a.arg, ptr %a.addr
  %b.addr = alloca ptr
  store ptr %b.arg, ptr %b.addr
  %ld130 = load ptr, ptr %$clo.addr
  %list_append.addr = alloca ptr
  store ptr %ld130, ptr %list_append.addr
  %ld131 = load ptr, ptr %a.addr
  %res_slot132 = alloca ptr
  %tgp133 = getelementptr i8, ptr %ld131, i64 8
  %tag134 = load i32, ptr %tgp133, align 4
  switch i32 %tag134, label %case_default10 [
      i32 0, label %case_br11
      i32 1, label %case_br12
  ]
case_br11:
  %ld135 = load ptr, ptr %a.addr
  call void @march_decrc(ptr %ld135)
  %ld136 = load ptr, ptr %b.addr
  store ptr %ld136, ptr %res_slot132
  br label %case_merge9
case_br12:
  %fp137 = getelementptr i8, ptr %ld131, i64 16
  %fv138 = load ptr, ptr %fp137, align 8
  %h.addr = alloca ptr
  store ptr %fv138, ptr %h.addr
  %fp139 = getelementptr i8, ptr %ld131, i64 24
  %fv140 = load ptr, ptr %fp139, align 8
  %t.addr = alloca ptr
  store ptr %fv140, ptr %t.addr
  %ld141 = load ptr, ptr %list_append.addr
  %fp142 = getelementptr i8, ptr %ld141, i64 16
  %fv143 = load ptr, ptr %fp142, align 8
  %ld144 = load ptr, ptr %t.addr
  %ld145 = load ptr, ptr %b.addr
  %cr146 = call ptr (ptr, ptr, ptr) %fv143(ptr %ld141, ptr %ld144, ptr %ld145)
  %$t196.addr = alloca ptr
  store ptr %cr146, ptr %$t196.addr
  %ld147 = load ptr, ptr %a.addr
  %tgp148 = getelementptr i8, ptr %ld147, i64 8
  store i32 1, ptr %tgp148, align 4
  %ld149 = load ptr, ptr %h.addr
  %fp150 = getelementptr i8, ptr %ld147, i64 16
  store ptr %ld149, ptr %fp150, align 8
  %ld151 = load ptr, ptr %$t196.addr
  %fp152 = getelementptr i8, ptr %ld147, i64 24
  store ptr %ld151, ptr %fp152, align 8
  store ptr %ld147, ptr %res_slot132
  br label %case_merge9
case_default10:
  unreachable
case_merge9:
  %case_r153 = load ptr, ptr %res_slot132
  ret ptr %case_r153
}

define ptr @collect_list$apply(ptr %$clo.arg, ptr %nodes.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %nodes.addr = alloca ptr
  store ptr %nodes.arg, ptr %nodes.addr
  %ld154 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld154)
  %ld155 = load ptr, ptr %$clo.addr
  %collect_list.addr = alloca ptr
  store ptr %ld155, ptr %collect_list.addr
  %ld156 = load ptr, ptr %$clo.addr
  %fp157 = getelementptr i8, ptr %ld156, i64 24
  %fv158 = load ptr, ptr %fp157, align 8
  %list_append.addr = alloca ptr
  store ptr %fv158, ptr %list_append.addr
  %ld159 = load ptr, ptr %nodes.addr
  %res_slot160 = alloca ptr
  %tgp161 = getelementptr i8, ptr %ld159, i64 8
  %tag162 = load i32, ptr %tgp161, align 4
  switch i32 %tag162, label %case_default14 [
      i32 0, label %case_br15
      i32 1, label %case_br16
  ]
case_br15:
  %ld163 = load ptr, ptr %nodes.addr
  %tgp164 = getelementptr i8, ptr %ld163, i64 8
  store i32 0, ptr %tgp164, align 4
  store ptr %ld163, ptr %res_slot160
  br label %case_merge13
case_br16:
  %fp165 = getelementptr i8, ptr %ld159, i64 16
  %fv166 = load ptr, ptr %fp165, align 8
  %h.addr = alloca ptr
  store ptr %fv166, ptr %h.addr
  %fp167 = getelementptr i8, ptr %ld159, i64 24
  %fv168 = load ptr, ptr %fp167, align 8
  %t.addr = alloca ptr
  store ptr %fv168, ptr %t.addr
  %ld169 = load ptr, ptr %nodes.addr
  call void @march_decrc(ptr %ld169)
  %ld170 = load ptr, ptr %h.addr
  %res_slot171 = alloca ptr
  %tgp172 = getelementptr i8, ptr %ld170, i64 8
  %tag173 = load i32, ptr %tgp172, align 4
  switch i32 %tag173, label %case_default18 [
      i32 0, label %case_br19
      i32 1, label %case_br20
      i32 2, label %case_br21
  ]
case_br19:
  %ld174 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld174)
  %hp175 = call ptr @march_alloc(i64 16)
  %tgp176 = getelementptr i8, ptr %hp175, i64 8
  store i32 0, ptr %tgp176, align 4
  store ptr %hp175, ptr %res_slot171
  br label %case_merge17
case_br20:
  %fp177 = getelementptr i8, ptr %ld170, i64 16
  %fv178 = load ptr, ptr %fp177, align 8
  %s.addr = alloca ptr
  store ptr %fv178, ptr %s.addr
  %ld179 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld179)
  %hp180 = call ptr @march_alloc(i64 16)
  %tgp181 = getelementptr i8, ptr %hp180, i64 8
  store i32 0, ptr %tgp181, align 4
  %$t197.addr = alloca ptr
  store ptr %hp180, ptr %$t197.addr
  %hp182 = call ptr @march_alloc(i64 32)
  %tgp183 = getelementptr i8, ptr %hp182, i64 8
  store i32 1, ptr %tgp183, align 4
  %ld184 = load ptr, ptr %s.addr
  %fp185 = getelementptr i8, ptr %hp182, i64 16
  store ptr %ld184, ptr %fp185, align 8
  %ld186 = load ptr, ptr %$t197.addr
  %fp187 = getelementptr i8, ptr %hp182, i64 24
  store ptr %ld186, ptr %fp187, align 8
  store ptr %hp182, ptr %res_slot171
  br label %case_merge17
case_br21:
  %fp188 = getelementptr i8, ptr %ld170, i64 16
  %fv189 = load ptr, ptr %fp188, align 8
  %ys.addr = alloca ptr
  store ptr %fv189, ptr %ys.addr
  %ld190 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld190)
  %ld191 = load ptr, ptr %collect_list.addr
  %fp192 = getelementptr i8, ptr %ld191, i64 16
  %fv193 = load ptr, ptr %fp192, align 8
  %ld194 = load ptr, ptr %ys.addr
  %cr195 = call ptr (ptr, ptr) %fv193(ptr %ld191, ptr %ld194)
  store ptr %cr195, ptr %res_slot171
  br label %case_merge17
case_default18:
  unreachable
case_merge17:
  %case_r196 = load ptr, ptr %res_slot171
  %parts.addr = alloca ptr
  store ptr %case_r196, ptr %parts.addr
  %ld197 = load ptr, ptr %collect_list.addr
  %fp198 = getelementptr i8, ptr %ld197, i64 16
  %fv199 = load ptr, ptr %fp198, align 8
  %ld200 = load ptr, ptr %t.addr
  %cr201 = call ptr (ptr, ptr) %fv199(ptr %ld197, ptr %ld200)
  %$t198.addr = alloca ptr
  store ptr %cr201, ptr %$t198.addr
  %ld202 = load ptr, ptr %list_append.addr
  %fp203 = getelementptr i8, ptr %ld202, i64 16
  %fv204 = load ptr, ptr %fp203, align 8
  %ld205 = load ptr, ptr %parts.addr
  %ld206 = load ptr, ptr %$t198.addr
  %cr207 = call ptr (ptr, ptr, ptr) %fv204(ptr %ld202, ptr %ld205, ptr %ld206)
  store ptr %cr207, ptr %res_slot160
  br label %case_merge13
case_default14:
  unreachable
case_merge13:
  %case_r208 = load ptr, ptr %res_slot160
  ret ptr %case_r208
}

define ptr @collect$apply(ptr %$clo.arg, ptr %node.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %node.addr = alloca ptr
  store ptr %node.arg, ptr %node.addr
  %ld209 = load ptr, ptr %$clo.addr
  %fp210 = getelementptr i8, ptr %ld209, i64 24
  %fv211 = load ptr, ptr %fp210, align 8
  %collect_list.addr = alloca ptr
  store ptr %fv211, ptr %collect_list.addr
  %ld212 = load ptr, ptr %node.addr
  %res_slot213 = alloca ptr
  %tgp214 = getelementptr i8, ptr %ld212, i64 8
  %tag215 = load i32, ptr %tgp214, align 4
  switch i32 %tag215, label %case_default23 [
      i32 0, label %case_br24
      i32 1, label %case_br25
      i32 2, label %case_br26
  ]
case_br24:
  %ld216 = load ptr, ptr %node.addr
  call void @march_decrc(ptr %ld216)
  %hp217 = call ptr @march_alloc(i64 16)
  %tgp218 = getelementptr i8, ptr %hp217, i64 8
  store i32 0, ptr %tgp218, align 4
  store ptr %hp217, ptr %res_slot213
  br label %case_merge22
case_br25:
  %fp219 = getelementptr i8, ptr %ld212, i64 16
  %fv220 = load ptr, ptr %fp219, align 8
  %s.addr = alloca ptr
  store ptr %fv220, ptr %s.addr
  %ld221 = load ptr, ptr %node.addr
  call void @march_decrc(ptr %ld221)
  %hp222 = call ptr @march_alloc(i64 16)
  %tgp223 = getelementptr i8, ptr %hp222, i64 8
  store i32 0, ptr %tgp223, align 4
  %$t199.addr = alloca ptr
  store ptr %hp222, ptr %$t199.addr
  %hp224 = call ptr @march_alloc(i64 32)
  %tgp225 = getelementptr i8, ptr %hp224, i64 8
  store i32 1, ptr %tgp225, align 4
  %ld226 = load ptr, ptr %s.addr
  %fp227 = getelementptr i8, ptr %hp224, i64 16
  store ptr %ld226, ptr %fp227, align 8
  %ld228 = load ptr, ptr %$t199.addr
  %fp229 = getelementptr i8, ptr %hp224, i64 24
  store ptr %ld228, ptr %fp229, align 8
  store ptr %hp224, ptr %res_slot213
  br label %case_merge22
case_br26:
  %fp230 = getelementptr i8, ptr %ld212, i64 16
  %fv231 = load ptr, ptr %fp230, align 8
  %xs.addr = alloca ptr
  store ptr %fv231, ptr %xs.addr
  %ld232 = load ptr, ptr %node.addr
  call void @march_decrc(ptr %ld232)
  %ld233 = load ptr, ptr %collect_list.addr
  %fp234 = getelementptr i8, ptr %ld233, i64 16
  %fv235 = load ptr, ptr %fp234, align 8
  %ld236 = load ptr, ptr %xs.addr
  %cr237 = call ptr (ptr, ptr) %fv235(ptr %ld233, ptr %ld236)
  store ptr %cr237, ptr %res_slot213
  br label %case_merge22
case_default23:
  unreachable
case_merge22:
  %case_r238 = load ptr, ptr %res_slot213
  ret ptr %case_r238
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
