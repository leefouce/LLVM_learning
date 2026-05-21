#!/usr/bin/env bash
# Ch7 演示：用 VM 本地的 alive-tv 做翻译验证（translation validation）。
#
# 运行：scripts/run.sh -- 'bash 07-alive2/demo.sh'
set -eu
cd "$(dirname "$0")"
PLUGIN=../05-custom-pass/build/libMul2Shl.so

verdict() {  # verdict <标题> <文件名(无后缀)>
  echo "==================== $1 ===================="
  alive-tv examples/"$2".ll 2>&1 | sed -n '/^define i/,$p' | tail -n 20
  echo
}

verdict "① 正确：mul x,8 → shl x,3" correct_mul2shl
verdict "② 错误：(x+1)>x ⇒ true（应给反例 INT_MAX）" wrong_overflow
verdict "③ Ch6 悬念：mul nsw x,8 → shl nsw x,3 对吗？" nsw_question
verdict "④ 错误：凭空加 nsw（target 比 source 更 poison）" wrong_add_nsw

echo "==================== ⑤ 压轴：验证 Ch5 自己写的 Pass ===================="
if [[ ! -f "$PLUGIN" ]]; then
  echo "✗ 还没构建插件，先跑： scripts/run.sh -- 'bash 05-custom-pass/build.sh'"
  exit 1
fi
echo "# 用插件把 pass_input.ll 变换成 after.ll，再交给 alive-tv 验证"
opt -load-pass-plugin="$PLUGIN" -passes=mul2shl -S examples/pass_input.ll -o /tmp/pass_after.ll 2>/dev/null
echo "--- 插件输出 ---"; sed -n '/^define/,/^}/p' /tmp/pass_after.ll
echo "--- alive-tv 结论 ---"; alive-tv examples/pass_input.ll /tmp/pass_after.ll 2>&1 | tail -6
