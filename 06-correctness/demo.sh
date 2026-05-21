#!/usr/bin/env bash
# Ch6 演示：nsw 标记如何影响优化器能否化简 (x+1) > x。
#
# 运行：scripts/run.sh -- 'bash 06-correctness/demo.sh'
set -eu
cd "$(dirname "$0")"

echo "######## 输入：with_nsw / without_nsw 两个版本 ########"
sed -n '/^define/,/^}/p' examples/overflow.ll

echo; echo "######## opt -passes=instcombine 之后 ########"
opt -passes=instcombine -S examples/overflow.ll | sed -n '/^define/,/^}/p'

cat <<'NOTE'

要点：
  with_nsw    → ret i1 true        （nsw 承诺不溢出，可放心折成 true）
  without_nsw → icmp ne x, 2147483647
                即「除 x=INT_MAX 外都为 true」——优化器不敢丢掉这个边界！
NOTE
