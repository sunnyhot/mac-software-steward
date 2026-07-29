#!/usr/bin/env bash
# 手测：sudo cask 自动提权。不进 CI（osascript 弹框无法自动化）。
#
# 用途：验证「brew upgrade --cask 卡 sudo 时，app 弹一次密码框批量重试」端到端可用。
#
# 前置：
#   1. 已构建 app：bash scripts/build-native.sh
#   2. 准备至少一个会触发 sudo 的 cask（装到 /usr/local 等需 root 写入位置）。
#
# 步骤：
#   - 打开 Mac 软件管家
#   - 在“检查并维护”的计划中选中会卡 sudo 的 cask，执行
#   - 观察：
#     a) 该包先显示「等待管理员授权」（needsSudo，锁盾图标）
#     b) 并发批结束后系统弹出原生密码框（一次，覆盖本批所有 needsSudo 包）
#     c) 输入密码后升级完成，状态变「完成」
#     d) 日志含「sudo 批次：osascript 提权执行 N 个 cask 升级」与 __RC__ 标记
#   - 负向：在密码框点取消 → 该包失败，action 允许「重试」（再点再弹框），而非「去终端」
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/build/MacSoftwareSteward.app"

if [ ! -d "$APP" ]; then
  echo "请先构建：bash scripts/build-native.sh" >&2
  exit 1
fi

echo "==> 启动 $APP 进行手测"
echo "    清单见此脚本顶部注释。"
open "$APP"
