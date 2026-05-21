; instcombine —— 窥孔/代数化简：把局部的小模式换成更简单的等价形式。
; 这里 2*x - x 应被化简成 x。
define i32 @f(i32 %x) {
  %m = mul i32 %x, 2
  %r = sub i32 %m, %x
  ret i32 %r
}
