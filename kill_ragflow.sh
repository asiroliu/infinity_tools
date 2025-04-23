#!/bin/bash
set -eo pipefail

# 配置参数
CONTAINER_NAME="ragflow-server"
TARGET_PROCESS="python3 api/ragflow_server.py"

# 检查容器运行状态（网页4方法增强）
if ! docker inspect "$CONTAINER_NAME" &>/dev/null; then
    echo "错误：容器 $CONTAINER_NAME 未运行！" >&2
    exit 2
fi

# 在容器内查找目标进程PID（网页5的进程过滤优化）
pids=$(docker exec "$CONTAINER_NAME" /usr/bin/bash -c \
    "ps -ef | grep -v grep | grep '${TARGET_PROCESS}' | awk '{print \$2}'")

# 添加进程信息展示（网页7的ps命令扩展）
show_process_info() {
    echo "进程状态报告："
    docker exec "$CONTAINER_NAME" /usr/bin/bash -c \
        "ps aux | grep -v grep | grep '${TARGET_PROCESS}'"
    echo "----------------------------------------"
}

if [ -z "$pids" ]; then
    echo "未找到正在运行的进程：$TARGET_PROCESS"
    exit 0
fi

# 终止前进程信息展示
show_process_info

# 强制终止进程（网页4的循环处理机制）
for pid in $pids; do
    echo "正在终止进程 $pid ..."
    docker exec "$CONTAINER_NAME" /usr/bin/bash -c "kill -9 $pid" 2>/dev/null || true
done

# 状态验证延迟（网页5的优雅退出机制扩展）
sleep 1

# 终止后进程信息验证
echo "终止后进程状态验证："
show_process_info

echo "✅ 所有 $TARGET_PROCESS 进程处理完成"