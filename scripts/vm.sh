#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# vm.sh — 底层 SSH / rsync 封装。被 run.sh 用 `source` 引入，不单独执行。
#
# 它做三件事：
#   1. 读取 scripts/.env 里的连接配置
#   2. vm_sync : 把整个仓库增量同步到 VM
#   3. vm_ssh  : 在 VM 上执行一条命令（stdout/stderr 原样带回）
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# 本脚本所在目录(scripts/) 与 仓库根目录
VM_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$VM_SH_DIR/.." && pwd)"

# ── 读配置 ───────────────────────────────────────────────────────────────────
ENV_FILE="$VM_SH_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "✗ 未找到 $ENV_FILE" >&2
  echo "  请: cp scripts/.env.example scripts/.env  然后填写 VM 连接信息。" >&2
  exit 1
fi
set -a; source "$ENV_FILE"; set +a   # set -a: 让 .env 里的变量自动 export

: "${VM_HOST:?请在 scripts/.env 设置 VM_HOST}"
: "${VM_USER:?请在 scripts/.env 设置 VM_USER}"
: "${VM_DIR:?请在 scripts/.env 设置 VM_DIR}"
VM_PORT="${VM_PORT:-22}"

# ── 组装 ssh 选项 ────────────────────────────────────────────────────────────
SSH_OPTS=(-p "$VM_PORT" -o StrictHostKeyChecking=accept-new)
[[ -n "${SSH_KEY:-}" ]] && SSH_OPTS+=(-i "$SSH_KEY")

# 在 VM 上执行命令字符串
vm_ssh() {
  ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "$@"
}

# 增量同步仓库到 VM:$VM_DIR（排除 .git / 真实 .env / 各章 build 产物）
vm_sync() {
  vm_ssh "mkdir -p '$VM_DIR'"
  rsync -az --delete \
    --exclude '.git' \
    --exclude 'scripts/.env' \
    --exclude '**/build/' \
    -e "ssh ${SSH_OPTS[*]}" \
    "$REPO_ROOT/" "$VM_USER@$VM_HOST:$VM_DIR/"
}

# 远程命令前缀：进入项目目录，并按需把 LLVM_BIN / ALIVE2_BIN 加进 PATH
vm_remote_prelude() {
  local p="cd '$VM_DIR'"
  [[ -n "${LLVM_BIN:-}" ]]   && p="$p && export PATH='$LLVM_BIN':\$PATH"
  [[ -n "${ALIVE2_BIN:-}" ]] && p="$p && export PATH='$ALIVE2_BIN':\$PATH"
  printf '%s' "$p"
}
