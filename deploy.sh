#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/home/infiniflow/workspace"
HAS_TAG=false
TARGET_TAG="nightly"
RETAIN_VOLUME=false
MODIFY_DOC_ENGINE=false
STOP_ONLY=false
QUIET_MODE=false
DEV_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
    -t)
        if [[ -z $2 ]]; then
            echo "错误：-t 参数需要指定镜像tag"
            exit 1
        fi
        TARGET_TAG="$2"
        HAS_TAG=true
        shift 2
        ;;
    -v)
        RETAIN_VOLUME=true
        shift
        ;;
    -s)
        STOP_ONLY=true
        shift
        ;;
    -i)
        MODIFY_DOC_ENGINE=true
        shift
        ;;
    -q)
        QUIET_MODE=true
        shift
        ;;
    -d)
        DEV_MODE=true
        shift
        ;;
    -h | --help)
        echo "Usage: $0 [-i] [-v] [-s] [-q] [-d] [-t TAG]"
        echo "Options:"
        echo "  -i          修改DOC_ENGINE配置为infinity"
        echo "  -v          保留Docker volume数据"
        echo "  -s          删除容器并清理volume"
        echo "  -t TAG      指定目标镜像标签"
        echo "  -q          静默模式，不显示服务日志"
        echo "  -d          使用源码方式启动"

        exit 0
        ;;
    *)
        echo "Usage: $0 [-i] [-v] [-s] [-q] [-t TAG]"
        echo "Options:"
        echo "  -i          修改DOC_ENGINE配置为infinity"
        echo "  -v          保留Docker volume数据"
        echo "  -s          删除容器并清理volume"
        echo "  -t TAG      指定目标镜像标签"
        echo "  -q          静默模式，不显示服务日志"
        echo "  -d          使用源码方式启动"

        exit 0
        ;;
    esac
done

if [[ "$HAS_TAG" == true ]]; then
    if [[ "$TARGET_TAG" =~ ^[0-9]+$ ]]; then
        RAGFLOW_HOME="${WORKSPACE}/${TARGET_TAG}"
    else
        RAGFLOW_HOME="${WORKSPACE}/ragflow"
    fi
else
    RAGFLOW_HOME="${WORKSPACE}/ragflow"
fi

declare -r RAGFLOW_HOME
declare -r COMPOSE_DIR="$RAGFLOW_HOME/docker"
declare -r ENV_FILE="$COMPOSE_DIR/.env"
declare -r TARGET_IMAGE="infiniflow/ragflow:${TARGET_TAG}"

delete_containers() {
    echo "▄ 强制删除指定容器..."
    local containers=(
        "ragflow-server"
        "ragflow-es-01"
        "ragflow-infinity"
        "ragflow-minio"
        "ragflow-redis"
        "ragflow-mysql"
    )

    for container in "${containers[@]}"; do
        if docker inspect --format='{{.Name}}' "$container" &>/dev/null; then
            if docker rm -f "$container" &>/dev/null; then
                echo "✅ 容器 $container 已删除"
            else
                echo "❌ 容器 $container 删除失败"
            fi
        else
            echo "⚠️ 容器 $container 不存在，跳过删除"
        fi
    done
}

delete_volumes() {
    echo "▄ 清理VOLUME..."
    local volumes=(
        "docker_esdata01"
        "docker_infinity_data"
        "docker_minio_data"
        "docker_mysql_data"
        "docker_redis_data"
    )

    for vol in "${volumes[@]}"; do
        if docker volume inspect "$vol" &>/dev/null; then
            if docker volume rm "$vol" >/dev/null; then
                echo "✅ Volume $vol 已成功删除"
            else
                echo "❌ Volume $vol 删除失败（可能仍有容器挂载）" >&2
            fi
        else
            echo "⚠️ Volume $vol 不存在，跳过删除"
        fi
    done
}

modify_env() {
    echo "▄ 更新目标镜像标签..."
    if sed -i "s#^RAGFLOW_IMAGE=.*#RAGFLOW_IMAGE=$TARGET_IMAGE#" "$ENV_FILE"; then
        echo "✅ 目标镜像标签已更新"
        echo "▄ $TARGET_IMAGE"
    else
        echo "❌ 目标镜像标签更新失败" >&2
        exit 4
    fi
}

modify_doc_engine() {
    echo "▄ 更新DOC_ENGINE配置..."
    local target_line="DOC_ENGINE=\${DOC_ENGINE:-elasticsearch}"
    local replacement="DOC_ENGINE=\${DOC_ENGINE:-infinity}"

    if sed -i "s#^${target_line}\$#${replacement}#" "$ENV_FILE"; then
        echo "✅ DOC_ENGINE=infinity"
    else
        echo "❌ DOC_ENGINE配置更新失败" >&2
        exit 8
    fi
}

start_services() {
    echo "▄ 启动新服务..."
    pushd "$COMPOSE_DIR" >/dev/null

    local compose_file="docker-compose.yml"
    if $DEV_MODE; then
        compose_file="docker-compose-base.yml"
        echo "✅ 使用 docker-compose-base.yml 启动"
    fi

    if [[ ! -f $compose_file ]]; then
        echo "❌ $compose_file 文件不存在" >&2
        exit 5
    fi

    local compose_cmd="docker compose"
    command -v docker-compose &>/dev/null && compose_cmd="docker-compose"

    local compose_up_args="-d"
    if $compose_cmd -f "$COMPOSE_DIR/$compose_file" up $compose_up_args; then
        echo "✅ 服务启动成功"
    else
        echo "❌ 服务启动失败" >&2
        exit 6
    fi

    popd >/dev/null
}

launch_service() {
    echo "▄ 启动新RagFlow后端服务..."
    pushd "$RAGFLOW_HOME" >/dev/null
    source .venv/bin/activate
    bash docker/launch_backend_service.sh
    popd >/dev/null
}

restore_env() {
    echo "▄ 恢复.env文件..."
    if git -C "$COMPOSE_DIR" restore "$ENV_FILE"; then
        echo "✅ 文件恢复成功"
    else
        echo "❌ 文件恢复失败（确认文件是否在Git管控中）" >&2
        exit 7
    fi
}

delete_containers

if ! $RETAIN_VOLUME; then
    delete_volumes
else
    echo "▄ 跳过清理VOLUME操作..."
fi

if ! $STOP_ONLY; then
    modify_env
    if $MODIFY_DOC_ENGINE; then
        modify_doc_engine
    fi
    start_services
    if $DEV_MODE; then
        launch_service
    fi
else
    echo "▄ 跳过启动新服务..."
fi

restore_env

echo "✅ 所有操作已完成"

if [[ "$DEV_MODE" != true && "$QUIET_MODE" == false && $STOP_ONLY != true ]]; then
    echo "▄ 显示服务日志..."
    docker logs -f ragflow-server
fi
