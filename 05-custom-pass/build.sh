#!/usr/bin/env bash
# 构建 Mul2Shl 插件。产物 build/Mul2Shl.so（或 lib... .so）。
#
# 运行：scripts/run.sh -- 'bash 05-custom-pass/build.sh'
# （build/ 已被 rsync 排除，构建产物只留在 VM、不会同步回 Mac）
set -euo pipefail
cd "$(dirname "$0")"

CMAKE_DIR="$(llvm-config --cmakedir)"   # LLVM 21 的 cmake 配置目录
echo "用 LLVM cmake 目录: $CMAKE_DIR"

cmake -S . -B build -DLLVM_DIR="$CMAKE_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j

echo "=== 产物 ==="
ls -la build/*.so
