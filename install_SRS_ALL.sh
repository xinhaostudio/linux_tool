#!/bin/bash

# SRS 一键安装脚本
# 适配系统：CentOS/RHEL/Rocky Linux/Ubuntu/Debian
# 功能：系统识别 + 交互确认 + 依赖安装 + 编译启动 + 端口检查

set -e  # 命令失败则终止脚本

# 颜色定义（终端兼容版）
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# 步骤提示函数
info() {
    echo -e "\n${GREEN}>>> $1${RESET}"
}

# 警告提示函数
warn() {
    echo -e "${YELLOW}提示：$1${RESET}"
}

# 错误提示函数
error() {
    echo -e "${RED}错误：$1${RESET}"
    exit 1
}

# 显示XinHaoStudio标识
show_logo() {
    echo -e "${CYAN}${BOLD}"
    echo "======================================"
    echo "          XinHaoStudio"
    echo "======================================"
    echo -e "     SRS 流媒体服务器一键安装工具"
    echo -e "          Version: 1.0.0 ${RESET}"
}

# 1. 显示标识并获取用户确认
show_logo
echo -e "\n该脚本将自动安装 SRS 流媒体服务器，包含以下步骤："
echo "1. 识别操作系统（RHEL 系/Debian 系）"
echo "2. 更新系统并安装依赖工具"
echo "3. 克隆 SRS 源码并编译（--full 全功能模式）"
echo "4. 启动服务并检查核心端口（1935/8554/8080）"

# 清晰显示Y/N颜色选项
echo -n "是否继续安装？(输入 ${GREEN}Y${RESET} 确认，${RED}N${RESET} 取消): "
read choice
case "$choice" in
    y|Y) echo -e "${GREEN}用户确认，开始安装...${RESET}" ;;
    *) echo -e "${RED}用户取消安装，脚本退出${RESET}"; exit 0 ;;
esac

# 2. 系统识别
info "识别操作系统..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ $ID =~ ^(centos|rhel|rocky)$ ]]; then
        PKG_MANAGER="yum"
        SYSTEM_TYPE="rhel"
    elif [[ $ID =~ ^(debian|ubuntu)$ ]]; then
        PKG_MANAGER="apt"
        SYSTEM_TYPE="debian"
    else
        error "不支持的操作系统：$ID（仅支持 RHEL/Debian 系）"
    fi
else
    error "无法识别操作系统（缺少 /etc/os-release 文件）"
fi
echo -e "已识别系统：${YELLOW}$PRETTY_NAME${RESET}（$SYSTEM_TYPE 系列）"

# 3. 进入用户主目录
info "进入用户主目录..."
cd ~ || error "无法进入主目录 ~"

# 4. 系统更新
info "更新系统包索引..."
if [ "$SYSTEM_TYPE" = "rhel" ]; then
    sudo $PKG_MANAGER update -y
else
    sudo $PKG_MANAGER update -y -qq  # Debian 系静默更新
fi

# 5. 安装基础依赖
info "安装编译工具链..."
if [ "$SYSTEM_TYPE" = "rhel" ]; then
    sudo $PKG_MANAGER install -y git gcc g++ make net-tools
else
    sudo $PKG_MANAGER install -y git gcc g++ make net-tools
fi

# 6. 克隆 SRS 源码
info "克隆 SRS 仓库（Gitee 镜像）..."
if [ -d "srs" ]; then
    warn "检测到已有 srs 目录，将删除旧目录重新克隆..."
    rm -rf srs
fi
git clone https://gitee.com/ossrs/srs.git || error "SRS 仓库克隆失败，请检查网络"

# 7. 进入源码目录
info "进入 SRS 源码目录..."
cd srs/trunk || error "无法进入 srs/trunk 目录"

# 8. 配置并编译（--full 全功能模式）
info "配置并编译 SRS（全功能模式）..."
echo -e "编译过程可能需要几分钟，请耐心等待..."
./configure --full && make || error "SRS 编译失败"

# 9. 停止可能存在的旧进程
info "确保旧 SRS 进程已停止..."
pkill srs >/dev/null 2>&1 || true

# 10. 启动 SRS 服务（默认配置）
info "启动 SRS 服务..."
./objs/srs -c conf/srs.conf || error "SRS 启动失败，请查看日志排查"

# 11. 检查服务状态
info "检查 SRS 服务状态..."
./etc/init.d/srs status || warn "服务状态检查警告（可能刚启动未就绪，建议稍后重试）"

# 12. 检查端口占用（核心端口：1935/8554/8080）
info "检查核心端口占用情况（1935=RTMP, 8554=RTSP, 8080=HTTP）..."
if sudo netstat -tulpn | grep -E "1935|8554|8080"; then
    echo -e "${GREEN}端口检查正常，服务已监听核心端口${RESET}"
else
    warn "未检测到端口占用，可能服务刚启动未就绪，建议 30 秒后手动检查："
    echo -e "sudo netstat -tulpn | grep -E '1935|8554|8080'"
fi

# 13. 显示实时日志（5秒预览）
info "显示实时日志（5秒后自动退出，可按 Ctrl+C 提前结束）..."
tail -f ./objs/srs.log &
TAIL_PID=$!
sleep 5
kill $TAIL_PID >/dev/null 2>&1

# 安装完成提示
info "安装完成！"
echo -e "\n${GREEN}=== SRS 流媒体服务器安装成功 ===${RESET}"
echo -e "📌 服务状态：./srs/trunk/etc/init.d/srs status"
echo -e "📌 停止服务：pkill srs"
echo -e "📌 查看日志：tail -f ./srs/trunk/objs/srs.log"
echo -e "📌 推流测试：ffmpeg -re -i input.mp4 -c copy -f flv rtmp://localhost/live/test"
echo -e "📌 核心端口：1935(RTMP)、8554(RTSP)、8080(HTTP/HLS)"
echo -e "\n${YELLOW}提示：如需开机自启，可手动配置系统服务（参考 SRS 官方文档）${RESET}"
