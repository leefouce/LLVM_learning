; sccp (Sparse Conditional Constant Propagation) —— 常量传播 + 死分支判定。
; %x 恒为 1，所以 %c 恒为 true，no 分支不可达。
define i32 @f() {
entry:
  %x = add i32 0, 1          ; 恒等于 1
  %c = icmp eq i32 %x, 1     ; 恒为 true
  br i1 %c, label %yes, label %no
yes:
  ret i32 42
no:                          ; 不可达
  ret i32 -1
}
