# 构建一个 out-of-tree 的 LLVM Pass 插件（.so），供 opt 用 -load-pass-plugin 加载。
cmake_minimum_required(VERSION 3.20)
project(Mul2Shl)

# 找到 LLVM。LLVM_DIR 由 build.sh 通过 `llvm-config --cmakedir` 传入。
find_package(LLVM REQUIRED CONFIG)
message(STATUS "找到 LLVM ${LLVM_PACKAGE_VERSION}，cmake 目录: ${LLVM_DIR}")

# 引入 LLVM 的编译选项（关键：让插件的 -fno-rtti 等设置和 LLVM 本体一致，
# 否则加载时会因 RTTI/ABI 不匹配出问题）。
list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}")
include(HandleLLVMOptions)
include(AddLLVM)

# 头文件与宏定义
include_directories(SYSTEM ${LLVM_INCLUDE_DIRS})
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND "${LLVM_DEFINITIONS}")
add_compile_definitions(${LLVM_DEFINITIONS_LIST})

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# MODULE 库 = 可被 dlopen 的插件。插件不链接 LLVM 库本体——
# 它用到的 LLVM 符号在加载时由 opt 进程提供（Linux 默认允许未定义符号）。
add_library(Mul2Shl MODULE Mul2Shl.cpp)
