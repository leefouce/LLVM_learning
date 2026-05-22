#!/usr/bin/env bash
# Ch1 演示：一个 C 函数走完  源码 → LLVM IR → 优化 → 汇编  全链路。
#
# 运行方式（在 Mac 上）：
#   scripts/run.sh -- 'bash 01-overview/demo.sh'
#
# 脚本在 VM 上执行，opt/clang/llc 已由 run.sh 自动加进 PATH。
set -euo pipefail
cd "$(dirname "$0")"          # 切到本章目录
T=/tmp/ch1                    # 中间产物放 /tmp，不污染项目
mkdir -p "$T"

echo "######## 1) 源码 hello.c ########"
cat hello.c

echo; echo "######## 2) Clang 前端 → 未优化 IR (-O0) ########"
echo "# clang -O0 -emit-llvm -S hello.c"
# -emit-llvm 让 clang 停在 IR 阶段；-S 出文本(.ll)而非 bitcode(.bc)
# -Xclang -disable-O0-optnone : 去掉 optnone 属性，否则后面 opt 不会优化它
clang -O0 -emit-llvm -S -Xclang -disable-O0-optnone hello.c -o "$T/hello.O0.ll"
cat "$T/hello.O0.ll"

echo; echo "######## 3) opt -O2 优化后的 IR ########"
echo "# opt -O2 -S hello.O0.ll"
opt -O2 -S "$T/hello.O0.ll" -o "$T/hello.O2.ll"
cat "$T/hello.O2.ll"

echo; echo "######## 4) llc 后端 → 目标汇编 ########"
echo "# llc -O2 hello.O2.ll   (只截取 sum_to 看闭式解)"
llc -O2 "$T/hello.O2.ll" -o "$T/hello.s"
cat "$T/hello.s"
