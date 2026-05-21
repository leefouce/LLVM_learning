#!/usr/bin/env bash
# Ch4 演示：用 opt -passes=... 单独跑各个优化 Pass，看 before/after。
#
# 运行：scripts/run.sh -- 'bash 04-opt-passes/demo.sh'
set -eu
cd "$(dirname "$0")"

# 小工具：show <标题> <passes> <文件> —— 打印输入函数体 + 跑完某 pass 后的函数体
show() {
  echo "######## $1 ########"
  echo "# opt -passes='$2'"
  echo "--- 输入 ---";  sed -n '/^define/,/^}/p' "$3"
  echo "--- 输出 ---";  opt -passes="$2" -S "$3" 2>/dev/null | sed -n '/^define/,/^}/p'
  echo
}

show "instcombine —— 代数化简：2*x - x → x" \
     "instcombine" examples/instcombine.ll

show "dce —— 删除无用指令 %dead" \
     "dce" examples/dce.ll

show "early-cse —— 公共子表达式消除：(x+y) 只算一次" \
     "early-cse" examples/gvn.ll

show "sccp —— 常量传播 + 删不可达块(no:)" \
     "sccp" examples/sccp.ll

show "sccp + simplifycfg —— 再把只剩一条边的 CFG 折平" \
     "sccp,simplifycfg" examples/sccp.ll

show "licm —— 把循环不变量 mul x,y 提到循环外" \
     "licm" examples/loop.ll

show "组合：mem2reg+simplifycfg+instcombine —— 直接认出 max 惯用法 → @llvm.smax" \
     "mem2reg,simplifycfg,instcombine" ../02-ir-basics/examples/max_mem.ll

echo "######## 分析型 Pass：print<domtree> 只「算信息」，不改 IR ########"
echo "# opt -passes='print<domtree>' -disable-output examples/loop.ll"
opt -passes="print<domtree>" -disable-output examples/loop.ll 2>&1 | head -8

echo; echo "######## 流水线 = 一串有序的 Pass：看 -O2 到底跑了啥（节选前 18 个）########"
echo "# opt -passes='default<O2>' -print-pipeline-passes -disable-output ..."
opt -passes="default<O2>" -print-pipeline-passes -disable-output examples/instcombine.ll 2>&1 \
  | tr ',' '\n' | grep -vE '^[[:space:]]*$' | head -18
