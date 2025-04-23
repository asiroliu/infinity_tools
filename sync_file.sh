#!/usr/bin/env bash
set -euo pipefail

# 配置参数（根据实际环境修改）
# LOCAL_ROOT="/home/infiniflow/workspace/ragflow"
LOCAL_ROOT="/home/infiniflow/workspace/rag_6239"
DOCKER_ROOT="/ragflow"
CONTAINER_NAME="ragflow-server"

# 校验输入参数
if [ $# -eq 0 ]; then
    echo "用法: $0 <相对路径1> [相对路径2] ..."
    echo "示例: $0 src/main.py config/settings.yaml"
    exit 1
fi

# 检查容器运行状态（网页9方法增强）
if ! docker inspect "$CONTAINER_NAME" &>/dev/null; then
    echo "错误：容器 $CONTAINER_NAME 未运行！" >&2
    exit 2
fi

# 处理每个输入路径
for rel_path in "$@"; do
    # 构造本地绝对路径（网页9路径处理优化）
    local_abs_path="${LOCAL_ROOT}/${rel_path#/}"
    
    # 验证本地路径存在性
    if [ ! -e "$local_abs_path" ]; then
        echo "警告：路径 '$rel_path' 不存在，已跳过" >&2
        continue
    fi

    # 计算容器内目标路径（网页11路径转换逻辑）
    docker_path="${DOCKER_ROOT}/${rel_path#/}"

    # 创建容器目录结构（网页9目录创建增强）
    docker exec "$CONTAINER_NAME" mkdir -p "$(dirname "$docker_path")"

    # 执行文件复制（网页10的docker cp命令）
    echo "同步中: $rel_path → $CONTAINER_NAME:$docker_path"
    docker cp "$local_abs_path" "$CONTAINER_NAME:$docker_path"

    # 递归设置权限（网页9权限方案升级）
    docker exec "$CONTAINER_NAME" chown -R root:root "$docker_path"
done

echo "✅ 同步完成！共处理 $# 个文件，权限已设置为 root:root"