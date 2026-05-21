; gvn / early-cse —— 公共子表达式消除：同一个值算两遍，只算一次。
; (x+y) 被算了两次，第二次应复用第一次的结果。
define i32 @f(i32 %x, i32 %y) {
  %a = add i32 %x, %y
  %b = add i32 %x, %y        ; 与 %a 完全相同 → 应复用 %a
  %r = mul i32 %a, %b
  ret i32 %r
}
