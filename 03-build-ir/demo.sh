#!/usr/bin/env bash
# Ch3 演示：用 llvmlite 编程构造 IR + JIT 执行；再用「系统 LLVM 21」验证兼容。
#
# 运行：scripts/run.sh -- 'bash 03-build-ir/demo.sh'
set -euo pipefail
cd "$(dirname "$0")"

PY="$HOME/.venvs/llvm-learning/bin/python"     # Ch3 专用的 Python 3.12 venv
if [[ ! -x "$PY" ]]; then
  echo "✗ 没找到 venv：$PY"
  echo "  先建一次（仅需一次）："
  echo "    ~/.local/bin/uv venv --python 3.12 ~/.venvs/llvm-learning"
  echo "    ~/.local/bin/uv pip install --python ~/.venvs/llvm-learning/bin/python llvmlite"
  exit 1
fi

echo "######## 1) llvmlite 构造 IR + JIT 执行 ########"
"$PY" build_ir.py

echo; echo "######## 2) 用系统 LLVM 21 校验 llvmlite 产出的 IR ########"
echo "# llvm-as (LLVM 20, llvmlite 自带) 生成的 IR，能否被 LLVM 21 接受？"
opt -passes=verify -disable-output /tmp/ch3.built.ll && echo "  LLVM 21 verify 通过 ✓（跨版本兼容）"

echo; echo "######## 3) 用系统 LLVM 21 的 llc 编成 aarch64 汇编 ########"
echo "# llc -O2 /tmp/ch3.built.ll"
llc -O2 /tmp/ch3.built.ll -o - | grep -A6 '^max:'
