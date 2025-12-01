#!/bin/bash
set -euo pipefail

local_mode=0
use_ssh=0
workspace="/home/infiniflow/workspace/python"
github_url=""
tag="main"
subdir="ragflow"
proxy_suffix=""

# 参数处理
while [[ $# -gt 0 ]]; do
    case "$1" in
    -s)
        use_ssh=1
        shift
        ;;
    -t)
        if [[ -z $2 ]]; then
            echo "错误：-t 参数需要指定镜像tag"
            exit 1
        fi
        tag="$2"
        shift 2
        ;;
    -w)
        if [[ -z $2 ]]; then
            echo "错误：-w 参数需要指定子目录"
            exit 1
        fi
        subdir="$2"
        shift 2
        ;;
    -p)
        if [[ -z $2 ]]; then
            echo "错误：-p 参数需要指定代理IP的最后一段数字"
            exit 1
        fi
        if ! [[ "$2" =~ ^[0-9]+$ ]]; then
            echo "错误：-p 参数必须是数字"
            exit 1
        fi
        proxy_suffix="$2"
        shift 2
        ;;
    -h | --help)
        echo "用法: $0 [-s] [-t TAG] [-w SUBDIR] [-p IP_SUFFIX] [GITHUB_URL]"
        echo "选项:"
        echo "  -s        使用SSH克隆协议"
        echo "  -t TAG    指定构建标签（默认：main）"
        echo "  -w SUBDIR 指定目标子目录（默认：ragflow）"
        echo "  -p IP_SUFFIX 指定代理IP的最后一段数字 (例如: 33)，将使用 192.168.1.IP_SUFFIX:7897 作为代理"
        echo "示例:"
        echo "  本地构建默认配置: $0"
        echo "  本地构建指定标签和目录: $0 -t 1.0 -w mydir"
        echo "  远程HTTPS构建并使用代理 (IP 192.168.1.33): $0 -p 33 https://github.com/user/repo"
        exit 0
        ;;
    *)
        if [[ -z "$github_url" ]]; then
            github_url="$1"
        else
            echo "错误：未知参数 $1"
            exit 1
        fi
        shift
        ;;
    esac
done

# 目录处理
if [[ -z "$github_url" ]]; then
    local_mode=1
    target_dir="${workspace}/${subdir}"
else
    if [[ "$subdir" == "ragflow" ]]; then
        target_dir="${workspace}/${tag}"
    else
        target_dir="${workspace}/${subdir}"
    fi
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
    if [ $use_ssh -eq 0 ]; then
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
# 参数: 代码目录 镜像标签 代理参数字符串
#######################################
build_docker_image() {
    local dir="$1" tag="$2" proxy_build_args="$3"

    echo "▸ 启动Docker构建..."
    pushd "$dir" >/dev/null
    
    echo "完整构建命令:"
    echo "DOCKER_BUILDKIT=1 docker build --progress=plain --build-arg NEED_MIRROR=1 ${proxy_build_args} -f Dockerfile -t \"infiniflow/ragflow:$tag\" ."
    
    DOCKER_BUILDKIT=1 docker build \
        --progress=plain \
        --build-arg NEED_MIRROR=1 \
        ${proxy_build_args} \
        -f Dockerfile \
        -t "infiniflow/ragflow:$tag" \
        . || {
        echo "✖ Docker构建失败" >&2
        exit 1
    }
    popd >/dev/null
}

print_variables() {
    echo "===== 当前变量配置 ====="
    echo "local_mode         = $local_mode"
    echo "use_ssh            = $use_ssh"
    echo "workspace          = $workspace"
    echo "github_url         = $github_url"
    echo "tag                = $tag"
    echo "subdir             = $subdir"
    echo "target_dir         = $target_dir"
    echo "proxy_suffix       = ${proxy_suffix:-<未设置>}"
    echo "========================="
}

main() {
    # 构造代理参数字符串
    local proxy_args_string=""
    if [[ -n "$proxy_suffix" ]]; then
        local full_ip="192.168.1.${proxy_suffix}"
        proxy_args_string="--build-arg http_proxy=http://${full_ip}:7897 --build-arg https_proxy=http://${full_ip}:7897 --build-arg all_proxy=socks5://${full_ip}:7897"
        echo "[代理配置] IP后缀: ${proxy_suffix} | 完整IP: ${full_ip}"
    fi
    
    print_variables
    
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
    build_docker_image "$target_dir" "$tag" "$proxy_args_string"

    echo "✔ 构建完成! 镜像名称: infiniflow/ragflow:$tag"
}

main