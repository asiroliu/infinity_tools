#!/bin/bash
set -euo pipefail

local_mode=0
use_lighten=0
use_https=0
positional_args=()

# 使用循环处理带选项的参数
while [[ $# -gt 0 ]]; do
    case "$1" in
    -l)
        use_lighten=1
        shift
        ;;
    -h)
        use_https=1
        shift
        ;;
    *)
        positional_args+=("$1")
        shift
        ;;
    esac
done

set -- "${positional_args[@]}"

# 参数处理逻辑优化
if [ $# -eq 0 ]; then
    # 本地模式参数
    local_mode=1
    target_dir="/home/infiniflow/workspace/python/ragflow"
    tag="main"
elif [ $# -ge 1 ] && [ $# -le 2 ]; then
    # 远程仓库模式
    github_url="$1"
    tag="${2:-main}"
    workspace="/home/infiniflow/workspace/python"
    target_dir="${workspace}/${tag}"
else
    echo "用法: $0 [-l] [-h] [<github_url> [tag]]" 
    echo "选项:"
    echo "  -h  使用HTTPS克隆协议"
    echo "  -l  构建精简版本"
    echo "示例:"
    echo "  远程HTTPS构建: $0 -h https://github.com/user/repo/tree/dev 1.0"
    echo "  远程SSH构建: $0 https://github.com/user/repo/tree/dev 1.0"
    exit 1
fi

#######################################
# GitHub仓库解析函数（支持HTTPS/SSH自动转换）
# 参数: GitHub URL
# 返回: 分支名 克隆地址
#######################################
parse_github_url() {
    local url="$1"

    # 提取分支名称
    if [[ $url == *"/tree/"* ]]; then
        branch=$(echo "$url" | awk -F '/tree/' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        repo_base="${url%/tree/*}"
    else
        branch="main"
        repo_base="$url"
    fi

    # 生成SSH克隆地址
    if [ $use_https -eq 1 ]; then
        clone_url="https://github.com/${repo_base#https://github.com/}.git"
    else
        clone_url="git@github.com:${repo_base#https://github.com/}.git"
    fi
    echo "$branch $clone_url"
}

#######################################
# 代码仓库更新/克隆操作
# 参数: 目标目录 分支名 克隆地址
#######################################
update_repository() {
    local dir="$1" branch="$2" url="$3"

    if [ -d "$dir" ]; then
        echo "▸ 检测到已有仓库，执行代码更新..."
        pushd "$dir" >/dev/null
        git reset --hard HEAD # 清除本地修改
        if ! git pull origin "$branch"; then
            echo "✖ 代码更新失败，请检查网络或权限" >&2
            exit 1
        fi
        popd >/dev/null
    else
        echo "▸ 执行首次代码克隆..."
        if ! git clone -b "$branch" --depth 1 "$url" "$dir"; then
            echo "✖ 克隆失败" >&2
            exit 1
        fi
    fi
}

#######################################
# 代码仓库验证
# 参数: 目标目录
#######################################
validate_local_repo() {
    local dir="$1"
    
    if [ ! -d "$dir" ]; then
        echo "✖ 本地代码目录不存在: $dir" >&2
        exit 1
    fi
    
    if [ ! -f "$dir/Dockerfile" ]; then
        echo "✖ 目录中未找到Dockerfile" >&2
        exit 1
    fi
}

#######################################
# Docker镜像构建
# 参数: 代码目录 镜像标签
#######################################
build_docker_image() {
    local dir="$1" tag="$2"

    local build_args=()
    if [ $use_lighten -eq 1 ]; then
        echo "▸ 构建slim版本..."
        build_args+=(--build-arg LIGHTEN=1)
    else
        echo "▸ 构建full版本..."
    fi

    echo "▸ 启动Docker构建..."
    pushd "$dir" >/dev/null
    DOCKER_BUILDKIT=1 docker build \
        --progress=plain \
        "${build_args[@]}" \
        --build-arg NEED_MIRROR=1 \
        -f Dockerfile \
        -t "infiniflow/ragflow:$tag" \
        . || {
        echo "✖ Docker构建失败" >&2
        exit 1
    }
    popd >/dev/null
}

main() {
    if [ $local_mode -eq 1 ]; then
        # 本地构建模式
        echo "[本地模式] 使用目录: $target_dir"
        validate_local_repo "$target_dir"
    else
        # 解析GitHub地址
        read -r branch clone_url <<<$(parse_github_url "$github_url")
        echo "[配置解析] 分支: $branch | 地址: $clone_url"

        # 创建工作目录
        mkdir -p "$workspace"

        # 代码管理
        update_repository "$target_dir" "$branch" "$clone_url"
    fi

    # Docker构建
    build_docker_image "$target_dir" "$tag"

    echo "✔ 构建完成! 镜像名称: infiniflow/ragflow:$tag"
}

main
