#!/usr/bin/env bash
# Ch2 演示：校验手写 IR、文本/二进制往返、以及 SSA 的来历(mem2reg)。
#
# 运行：scripts/run.sh -- 'bash 02-ir-basics/demo.sh'
set -euo pipefail
cd "$(dirname "$0")"

echo "######## 1) 校验三个手写 IR 是否合法 ########"
for f in examples/max.ll examples/max_mem.ll examples/gep.ll; do
  opt -passes=verify -disable-output "$f" && echo "  OK  $f"
done

echo; echo "######## 2) 文本 .ll ↔ 二进制 .bc 往返 ########"
echo "# llvm-as：.ll → .bc(汇编)，llvm-dis：.bc → .ll(反汇编)"
llvm-as examples/max.ll -o /tmp/max.bc
llvm-dis /tmp/max.bc -o /tmp/max.from_bc.ll
echo "  max.bc = $(wc -c < /tmp/max.bc) 字节(二进制) ；反汇编回 .ll 成功"

echo; echo "######## 3) SSA 的来历：mem2reg 把 alloca 形式 → phi 形式 ########"
echo "--- 输入：max_mem.ll（alloca/load/store，非 SSA）---"
cat examples/max_mem.ll
echo
echo "--- opt -passes=mem2reg 之后（alloca 消失，end 块出现 phi）---"
opt -passes=mem2reg -S examples/max_mem.ll -o -

echo; echo "######## 4) 用 lli 直接解释执行（验证 max 真的对）########"
# lli 需要 main。这里临时拼一个 main 调用 max(7,3) 并把结果当退出码。
cat > /tmp/driver.ll <<'EOF'
declare i32 @max(i32, i32)
define i32 @main() {
  %r = call i32 @max(i32 7, i32 3)
  ret i32 %r            ; 把结果作为进程退出码
}
EOF
llvm-link examples/max.ll /tmp/driver.ll -S -o /tmp/linked.ll
set +e
lli /tmp/linked.ll
echo "  max(7,3) 的返回值(退出码) = $?   （应为 7）"
