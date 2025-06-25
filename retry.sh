#!/usr/bin/env bash
set -eo pipefail

# 检查是否传入命令
if [ $# -eq 0 ]; then
    echo "错误：请指定要重试的命令"
    echo "示例：$0 <command> [args...]"
    exit 1
fi

echo "▶ 开始持续重试命令：$*"

# 无限重试（按 Ctrl+C 终止）
while true; do
    if "$@"; then
        echo "✅ 命令执行成功！"
        exit 0
    else
        echo "❌ 命令失败，立即重试..."
    fi
done
