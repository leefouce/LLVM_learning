#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# run.sh — ★ 通用入口 ★
#
# 把仓库同步到 VM，然后在 VM 上运行你给的 LLVM 命令，输出原样回显。
# 这是你以后测试任何 LLVM 例子的唯一入口。
#
# 两种用法：
#   1) 工具 + 参数（最常用）：
#        scripts/run.sh opt --version
#        scripts/run.sh clang -O0 -emit-llvm -S 01-overview/hello.c -o -
#        scripts/run.sh opt -passes='mem2reg,instcombine' -S file.ll -o -
#        scripts/run.sh alive-tv before.ll after.ll
#
#   2) 整条 shell 命令（需要管道/重定向时，用 -- 开头）：
#        scripts/run.sh -- "opt -O2 -S a.ll | llc -o -"
#
# 注意：命令里的文件路径相对【仓库根目录】（VM 上同步过去的同一份）。
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vm.sh"

if [[ $# -eq 0 ]]; then
  echo "用法: scripts/run.sh <llvm工具> [参数...]   或   scripts/run.sh -- '整条命令'" >&2
  exit 2
fi

vm_sync                            # 先把最新代码推到 VM
prelude="$(vm_remote_prelude)"     # cd 到项目目录 (+ 可选 PATH)

if [[ "${1:-}" == "--" ]]; then
  shift
  vm_ssh "$prelude && $*"          # 原样执行整条命令（支持管道）
else
  # 把每个参数安全转义后拼成远程命令，避免空格/引号问题
  cmd=""
  for a in "$@"; do cmd+=" $(printf '%q' "$a")"; done
  vm_ssh "$prelude &&$cmd"
fi
