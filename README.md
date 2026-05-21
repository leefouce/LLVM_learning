# LLVM 两天上手（IR · 优化 Pass · 验证 / Alive2）

用「读概念 → 跑脚本 → 看结果」的方式，两天掌握 LLVM 核心。
全链路只给宏观概念，重点在 **IR + 优化 Pass + 验证**，最后单独一章学 **Alive2**。

## 环境模型

- 代码住在这台 **Mac** 的 git 仓库里。
- LLVM / Alive2 装在**虚拟机 (VM)** 上。
- 所有命令通过 `scripts/run.sh` **同步到 VM 运行**，输出回显到本机。

```
你在 Mac 写/改文件  ──rsync──▶  VM 上同一份  ──运行 opt/clang/llc/alive-tv──▶  输出带回 Mac
```

## 一次性配置

**(1) SSH 连接**（所有章节都需要）：
```bash
cp scripts/.env.example scripts/.env
# 编辑 scripts/.env，填 VM_HOST / VM_USER / VM_PORT / SSH_KEY / VM_DIR
#   以及 LLVM_BIN（LLVM 21 的 bin）/ ALIVE2_BIN（alive-tv 所在目录）
scripts/run.sh opt --version        # 验证连通 + 看 LLVM 版本
```
`scripts/.env` 不会进 git（凭据安全）。本仓库当前 VM 用的是 **LLVM 21.1.6 + Alive2 同版本**。

**(2) Ch3 的 Python 环境**（只在跑 03-build-ir 时需要，已在 VM 配好）：
```bash
scripts/run.sh -- '~/.local/bin/uv venv --python 3.12 ~/.venvs/llvm-learning && \
  ~/.local/bin/uv pip install --python ~/.venvs/llvm-learning/bin/python llvmlite'
```

**(3) Ch5 的插件构建**（只在跑 05-custom-pass / 07-alive2 压轴时需要）：
```bash
scripts/run.sh -- 'bash 05-custom-pass/build.sh'
```

## 通用入口：scripts/run.sh

以后测试**任何** LLVM 例子都用它（路径相对仓库根目录）：

```bash
scripts/run.sh clang -O0 -emit-llvm -S 01-overview/hello.c -o -   # C → IR
scripts/run.sh opt -passes='mem2reg,instcombine' -S file.ll -o -  # 跑指定 pass
scripts/run.sh llc -O2 file.ll -o -                               # IR → 汇编
scripts/run.sh alive-tv before.ll after.ll                        # 验证优化正确性
scripts/run.sh -- "opt -O2 -S a.ll | llc -o -"                    # 任意管道命令
```

## 2 天路线图

| 章节 | 主题 | 重点 |
|----|----|----|
| [01-overview](01-overview/)   | 宏观全链路：源码→IR→优化→汇编 | 概念 |
| [02-ir-basics](02-ir-basics/) | LLVM IR 语言精讲（SSA / 指令 / phi / GEP） | ★ |
| [03-build-ir](03-build-ir/)   | 用 Python(llvmlite) 以编程方式构造 IR | |
| [04-opt-passes](04-opt-passes/) | 优化 Pass 与 `opt` 实战，看 before/after diff | ★ |
| [05-custom-pass](05-custom-pass/) | 写一个注释版 C++ Pass（新 PM 插件） | |
| [06-correctness](06-correctness/) | 优化为什么会错：UB / poison / nsw / freeze | |
| [07-alive2](07-alive2/)       | Alive2 翻译验证（在线版 + VM 本地 alive-tv） | ★ |

Day 1 = 01–03，Day 2 = 04–07。每章 `notes.md` 自带可跑命令和预期输出，`demo.sh` 一键演示：
```bash
scripts/run.sh -- 'bash 01-overview/demo.sh'   # 把 01 换成任意章节目录
```

## 测试你自己的例子（速查）

写好一个 `.c` 或 `.ll`（放仓库任意位置），用 `scripts/run.sh` 一条命令测：

```bash
# C 源码看 IR / 优化 / 汇编
scripts/run.sh clang -O0 -emit-llvm -S -Xclang -disable-O0-optnone my.c -o -
scripts/run.sh -- 'clang -O0 -emit-llvm -S my.c -o - | opt -O2 -S'
scripts/run.sh clang -O2 -S my.c -o -                       # 直接出汇编

# 手写/已有 .ll 跑某个 pass，看 before/after
scripts/run.sh opt -passes='mem2reg,instcombine,gvn' -S my.ll -o -
scripts/run.sh opt -passes='default<O2>' -S my.ll -o -      # 整套 O2

# 校验 IR 合法性
scripts/run.sh opt -passes=verify -disable-output my.ll

# 用 Alive2 验证一个优化是否正确（my.ll 里写 @src 和 @tgt 两个函数）
scripts/run.sh alive-tv my.ll
scripts/run.sh alive-tv --smt-to=30000 my.ll                # 乘法等复杂例子调大超时

# 跑自己写的 Pass（先 build.sh 过一次）
scripts/run.sh opt -load-pass-plugin=05-custom-pass/build/libMul2Shl.so \
  -passes=mul2shl -S my.ll -o -
```
