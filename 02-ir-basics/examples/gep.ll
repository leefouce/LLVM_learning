; gep.ll — getelementptr (GEP)：只算「地址」，不碰内存。是 LLVM 里最容易绕晕的指令。
;
; 关键点：GEP 不读不写，它只做指针算术 —— 给定基址和一串下标，算出元素地址。
; 要真正取值，还得再来一条 load。

; @arr : 一个全局的、长度 4 的 i32 数组 = [10, 20, 30, 40]
@arr = global [4 x i32] [i32 10, i32 20, i32 30, i32 40]

; 返回 arr[i]
define i32 @get(i32 %i) {
  ; getelementptr [4 x i32], ptr @arr, i64 0, i64 %i
  ;   第 1 个下标 0 ：先「穿过」指向数组的指针本身（数组没动）
  ;   第 2 个下标 i ：在 [4 x i32] 内部走到第 i 个元素
  ; 结果 %p 是 &arr[i]，类型是 ptr。
  %idx = sext i32 %i to i64                                  ; 下标扩成 i64
  %p = getelementptr inbounds [4 x i32], ptr @arr, i64 0, i64 %idx
  %v = load i32, ptr %p                                      ; v = arr[i]
  ret i32 %v
}
