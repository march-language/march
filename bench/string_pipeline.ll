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

@.str1 = private unnamed_addr constant [2 x i8] c",\00"

define ptr @build_list(i64 %lo.arg, i64 %hi.arg, ptr %acc.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1 = load i64, ptr %lo.addr
  %ld2 = load i64, ptr %hi.addr
  %cmp3 = icmp sgt i64 %ld1, %ld2
  %ar4 = zext i1 %cmp3 to i64
  %$t574.addr = alloca i64
  store i64 %ar4, ptr %$t574.addr
  %ld5 = load i64, ptr %$t574.addr
  %res_slot6 = alloca ptr
  switch i64 %ld5, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %ld7 = load ptr, ptr %acc.addr
  store ptr %ld7, ptr %res_slot6
  br label %case_merge1
case_default2:
  %ld8 = load i64, ptr %lo.addr
  %ar9 = add i64 %ld8, 1
  %$t575.addr = alloca i64
  store i64 %ar9, ptr %$t575.addr
  %ld10 = load i64, ptr %lo.addr
  %cr11 = call ptr @march_int_to_string(i64 %ld10)
  %$t576.addr = alloca ptr
  store ptr %cr11, ptr %$t576.addr
  %hp12 = call ptr @march_alloc(i64 32)
  %tgp13 = getelementptr i8, ptr %hp12, i64 8
  store i32 1, ptr %tgp13, align 4
  %ld14 = load ptr, ptr %$t576.addr
  %fp15 = getelementptr i8, ptr %hp12, i64 16
  store ptr %ld14, ptr %fp15, align 8
  %ld16 = load ptr, ptr %acc.addr
  %fp17 = getelementptr i8, ptr %hp12, i64 24
  store ptr %ld16, ptr %fp17, align 8
  %$t577.addr = alloca ptr
  store ptr %hp12, ptr %$t577.addr
  %ld18 = load i64, ptr %$t575.addr
  %ld19 = load i64, ptr %hi.addr
  %ld20 = load ptr, ptr %$t577.addr
  %cr21 = call ptr @build_list(i64 %ld18, i64 %ld19, ptr %ld20)
  store ptr %cr21, ptr %res_slot6
  br label %case_merge1
case_merge1:
  %case_r22 = load ptr, ptr %res_slot6
  ret ptr %case_r22
}

define ptr @double_str(ptr %s.arg) {
entry:
  %s.addr = alloca ptr
  store ptr %s.arg, ptr %s.addr
  %ld23 = load ptr, ptr %s.addr
  call void @march_incrc(ptr %ld23)
  %ld24 = load ptr, ptr %s.addr
  %cr25 = call ptr @march_string_to_int(ptr %ld24)
  %$t578.addr = alloca ptr
  store ptr %cr25, ptr %$t578.addr
  %ld26 = load ptr, ptr %$t578.addr
  %res_slot27 = alloca ptr
  %tgp28 = getelementptr i8, ptr %ld26, i64 8
  %tag29 = load i32, ptr %tgp28, align 4
  switch i32 %tag29, label %case_default5 [
      i32 1, label %case_br6
      i32 0, label %case_br7
  ]
case_br6:
  %fp30 = getelementptr i8, ptr %ld26, i64 16
  %fv31 = load ptr, ptr %fp30, align 8
  %n.addr = alloca ptr
  store ptr %fv31, ptr %n.addr
  %ld32 = load ptr, ptr %$t578.addr
  call void @march_decrc(ptr %ld32)
  %ld33 = load i64, ptr %n.addr
  %ld34 = load i64, ptr %n.addr
  %ar35 = add i64 %ld33, %ld34
  %sr_s1.addr = alloca i64
  store i64 %ar35, ptr %sr_s1.addr
  %ld36 = load i64, ptr %sr_s1.addr
  %$t579.addr = alloca i64
  store i64 %ld36, ptr %$t579.addr
  %ld37 = load i64, ptr %$t579.addr
  %cr38 = call ptr @march_int_to_string(i64 %ld37)
  store ptr %cr38, ptr %res_slot27
  br label %case_merge4
case_br7:
  %ld39 = load ptr, ptr %$t578.addr
  call void @march_decrc(ptr %ld39)
  %ld40 = load ptr, ptr %s.addr
  store ptr %ld40, ptr %res_slot27
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r41 = load ptr, ptr %res_slot27
  ret ptr %case_r41
}

define ptr @map_strings(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld42 = load ptr, ptr %xs.addr
  %res_slot43 = alloca ptr
  %tgp44 = getelementptr i8, ptr %ld42, i64 8
  %tag45 = load i32, ptr %tgp44, align 4
  switch i32 %tag45, label %case_default9 [
      i32 0, label %case_br10
      i32 1, label %case_br11
  ]
case_br10:
  %ld46 = load ptr, ptr %xs.addr
  %rc47 = load i64, ptr %ld46, align 8
  %uniq48 = icmp eq i64 %rc47, 1
  %fbip_slot49 = alloca ptr
  br i1 %uniq48, label %fbip_reuse12, label %fbip_fresh13
fbip_reuse12:
  %tgp50 = getelementptr i8, ptr %ld46, i64 8
  store i32 0, ptr %tgp50, align 4
  store ptr %ld46, ptr %fbip_slot49
  br label %fbip_merge14
fbip_fresh13:
  call void @march_decrc(ptr %ld46)
  %hp51 = call ptr @march_alloc(i64 16)
  %tgp52 = getelementptr i8, ptr %hp51, i64 8
  store i32 0, ptr %tgp52, align 4
  store ptr %hp51, ptr %fbip_slot49
  br label %fbip_merge14
fbip_merge14:
  %fbip_r53 = load ptr, ptr %fbip_slot49
  store ptr %fbip_r53, ptr %res_slot43
  br label %case_merge8
case_br11:
  %fp54 = getelementptr i8, ptr %ld42, i64 16
  %fv55 = load ptr, ptr %fp54, align 8
  %h.addr = alloca ptr
  store ptr %fv55, ptr %h.addr
  %fp56 = getelementptr i8, ptr %ld42, i64 24
  %fv57 = load ptr, ptr %fp56, align 8
  %t.addr = alloca ptr
  store ptr %fv57, ptr %t.addr
  %ld58 = load ptr, ptr %h.addr
  %cr59 = call ptr @double_str(ptr %ld58)
  %$t580.addr = alloca ptr
  store ptr %cr59, ptr %$t580.addr
  %ld60 = load ptr, ptr %t.addr
  %cr61 = call ptr @map_strings(ptr %ld60)
  %$t581.addr = alloca ptr
  store ptr %cr61, ptr %$t581.addr
  %ld62 = load ptr, ptr %xs.addr
  %ld63 = load ptr, ptr %$t580.addr
  %ld64 = load ptr, ptr %$t581.addr
  %rc65 = load i64, ptr %ld62, align 8
  %uniq66 = icmp eq i64 %rc65, 1
  %fbip_slot67 = alloca ptr
  br i1 %uniq66, label %fbip_reuse15, label %fbip_fresh16
fbip_reuse15:
  %tgp68 = getelementptr i8, ptr %ld62, i64 8
  store i32 1, ptr %tgp68, align 4
  %fp69 = getelementptr i8, ptr %ld62, i64 16
  store ptr %ld63, ptr %fp69, align 8
  %fp70 = getelementptr i8, ptr %ld62, i64 24
  store ptr %ld64, ptr %fp70, align 8
  store ptr %ld62, ptr %fbip_slot67
  br label %fbip_merge17
fbip_fresh16:
  call void @march_decrc(ptr %ld62)
  %hp71 = call ptr @march_alloc(i64 32)
  %tgp72 = getelementptr i8, ptr %hp71, i64 8
  store i32 1, ptr %tgp72, align 4
  %fp73 = getelementptr i8, ptr %hp71, i64 16
  store ptr %ld63, ptr %fp73, align 8
  %fp74 = getelementptr i8, ptr %hp71, i64 24
  store ptr %ld64, ptr %fp74, align 8
  store ptr %hp71, ptr %fbip_slot67
  br label %fbip_merge17
fbip_merge17:
  %fbip_r75 = load ptr, ptr %fbip_slot67
  store ptr %fbip_r75, ptr %res_slot43
  br label %case_merge8
case_default9:
  unreachable
case_merge8:
  %case_r76 = load ptr, ptr %res_slot43
  ret ptr %case_r76
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 100000, ptr %n.addr
  %hp77 = call ptr @march_alloc(i64 16)
  %tgp78 = getelementptr i8, ptr %hp77, i64 8
  store i32 0, ptr %tgp78, align 4
  %$t582.addr = alloca ptr
  store ptr %hp77, ptr %$t582.addr
  %ld79 = load i64, ptr %n.addr
  %ld80 = load ptr, ptr %$t582.addr
  %cr81 = call ptr @build_list(i64 1, i64 %ld79, ptr %ld80)
  %pieces.addr = alloca ptr
  store ptr %cr81, ptr %pieces.addr
  %ld82 = load ptr, ptr %pieces.addr
  %cr83 = call ptr @map_strings(ptr %ld82)
  %doubled.addr = alloca ptr
  store ptr %cr83, ptr %doubled.addr
  %ld84 = load ptr, ptr %doubled.addr
  %sl85 = call ptr @march_string_lit(ptr @.str1, i64 1)
  %cr86 = call ptr @march_string_join(ptr %ld84, ptr %sl85)
  %result.addr = alloca ptr
  store ptr %cr86, ptr %result.addr
  %ld87 = load ptr, ptr %result.addr
  %cr88 = call i64 @march_string_byte_length(ptr %ld87)
  %$t583.addr = alloca i64
  store i64 %cr88, ptr %$t583.addr
  %ld89 = load i64, ptr %$t583.addr
  %cr90 = call ptr @march_int_to_string(i64 %ld89)
  %$t584.addr = alloca ptr
  store ptr %cr90, ptr %$t584.addr
  %ld91 = load ptr, ptr %$t584.addr
  call void @march_println(ptr %ld91)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
