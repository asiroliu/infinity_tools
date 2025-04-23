#!/usr/bin/env bash
set -euo pipefail

# 定义基础镜像名称
ORIGIN_IMAGE="infiniflow/ragflow:nightly"

# ========== 镜像重命名模块 ==========
if docker image inspect "$ORIGIN_IMAGE" &>/dev/null; then
    # 获取前一天日期（兼容Mac/Linux）
    if date --version &>/dev/null; then
        yesterday=$(date -d "yesterday" +%Y%m%d)  # Linux
    else
        yesterday=$(date -v-1d +%Y%m%d)           # MacOS
    fi

    # 生成新镜像标签
    NEW_IMAGE="${ORIGIN_IMAGE}-${yesterday}"
    echo "▸ 检测到旧镜像，执行重命名: $NEW_IMAGE"

    # 执行镜像重命名
    docker tag "$ORIGIN_IMAGE" "$NEW_IMAGE" && echo "✔ 镜像重命名成功"

    # 删除原标签
    echo "▸ 删除原镜像标签..."
    if docker rmi "$ORIGIN_IMAGE" 2>/dev/null; then
        echo "✔ 原标签删除成功"
    else
        echo "⚠ 原标签删除失败（可能已被其他操作删除）"
    fi
else
    echo "⏭ 原镜像不存在，跳过重命名步骤"
fi

# ========== 镜像拉取模块 ==========
echo "▸ 正在静默拉取最新镜像..."
if docker pull -q "$ORIGIN_IMAGE" >/dev/null; then
    echo "✔ 镜像拉取完成"
else
    echo "✖ 镜像拉取失败" >&2
    exit 1
fi
