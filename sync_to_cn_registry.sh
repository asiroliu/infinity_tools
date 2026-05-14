#!/bin/bash

# =================================================================
# 脚本名称: sync_to_cn_registry.sh
# 脚本作用: 将 Docker Hub 镜像同步至华为云(SWR)和阿里云(ACR)
# 使用方法: ./sync_to_cn_registry.sh <TAG>
# =================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 1. 参数校验
if [ -z "$1" ]; then
    echo -e "${RED}[ERROR]${NC} 未提供版本号 (Tag)。"
    echo -e "用法: $0 v0.25.2"
    exit 1
fi

TAG=$1
SOURCE_IMAGE="infiniflow/ragflow"
HUAWEI_REPO="swr.cn-north-4.myhuaweicloud.com/infiniflow/ragflow"
ALIYUN_REPO="registry.cn-hangzhou.aliyuncs.com/infiniflow/ragflow"

# 报错即停止
set -e

# 日志函数
log_header() {
    echo -e "\n${BLUE}================================================================${NC}"
    echo -e "${CYAN}[$(date +'%H:%M:%S')] $1${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

# 记录总开始时间
START_TIME=$(date +%s)

# ---------------------------------------------------------
log_header "STEP 1: 从 Docker Hub 拉取源镜像"
echo -e "${GREEN}执行命令:${NC} docker pull ${SOURCE_IMAGE}:${TAG}"
set -x
docker pull ${SOURCE_IMAGE}:${TAG}
{ set +x; } 2>/dev/null

# ---------------------------------------------------------
log_header "STEP 2: 生成国内源镜像标签 (Tagging)"
echo -e "${GREEN}执行命令:${NC}"
set -x
docker tag ${SOURCE_IMAGE}:${TAG} ${HUAWEI_REPO}:${TAG}
docker tag ${SOURCE_IMAGE}:${TAG} ${HUAWEI_REPO}:latest
docker tag ${SOURCE_IMAGE}:${TAG} ${ALIYUN_REPO}:${TAG}
docker tag ${SOURCE_IMAGE}:${TAG} ${ALIYUN_REPO}:latest
{ set +x; } 2>/dev/null

# ---------------------------------------------------------
log_header "STEP 3: 推送镜像至华为云 SWR"
echo -e "${GREEN}执行命令:${NC} docker push ${HUAWEI_REPO} ..."
set -x
docker push ${HUAWEI_REPO}:${TAG}
docker push ${HUAWEI_REPO}:latest
{ set +x; } 2>/dev/null

# ---------------------------------------------------------
log_header "STEP 4: 推送镜像至阿里云 ACR"
echo -e "${GREEN}执行命令:${NC} docker push ${ALIYUN_REPO} ..."
set -x
docker push ${ALIYUN_REPO}:${TAG}
docker push ${ALIYUN_REPO}:latest
{ set +x; } 2>/dev/null

# ---------------------------------------------------------
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo -e "\n${GREEN}✨ 同步任务圆满完成!${NC}"
echo -e "${CYAN}总耗时: ${DURATION} 秒${NC}\n"

# ---------------------------------------------------------
echo -e "\n${GREEN}🧹 手动删除本地镜像 (可选):${NC}"
echo -e "${YELLOW}# 删除阿里云镜像${NC}"
echo "docker rmi ${ALIYUN_REPO}:${TAG}"
echo "docker rmi ${ALIYUN_REPO}:latest"
echo -e "${YELLOW}# 删除华为云镜像${NC}"
echo "docker rmi ${HUAWEI_REPO}:${TAG}"
echo "docker rmi ${HUAWEI_REPO}:latest"
echo -e "${YELLOW}# 删除源镜像 (Docker Hub)${NC}"
echo "docker rmi ${SOURCE_IMAGE}:${TAG}"