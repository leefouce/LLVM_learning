; 验证：mul x, 8（无标记）→ shl nsw x, 3（凭空加上 nsw 承诺）—— 是否合法？
; 直觉：src 对所有 x 都有定义（会回绕）；tgt 在溢出时变 poison。
;       tgt 比 src「更挑剔/更未定义」，违反精化方向 → 应为【错误】。
; 预期：Alive2 给反例（某个让 x*8 溢出的 x，如 2^28）。
define i32 @src(i32 %x) {
  %r = mul i32 %x, 8
  ret i32 %r
}
define i32 @tgt(i32 %x) {
  %r = shl nsw i32 %x, 3
  ret i32 %r
}
