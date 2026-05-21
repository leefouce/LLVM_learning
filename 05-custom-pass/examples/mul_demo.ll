; 给 Mul2Shl 插件用的测试输入。
define i32 @f(i32 %x, i32 %y) {
  %a = mul i32 %x, 8        ; 8 = 2^3   → 应变成 shl %x, 3
  %b = mul i32 %y, 16       ; 16 = 2^4  → 应变成 shl %y, 4
  %c = mul i32 %a, 3        ; 3 不是 2 的幂 → 保持 mul 不动
  %d = add i32 %c, %b
  ret i32 %d
}
