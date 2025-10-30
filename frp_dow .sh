#!/bin/bash

# ===============================
# LoCyanFrp 自动安装脚本（最终版，修正语法错误）
# 逻辑：下载 -> 解压 -> 删除压缩包 -> 保持在当前目录
# ===============================

#by热冰块hic，chatGPT
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# 下载地址配置
declare -A DOWNLOAD_URLS=(
    ["aarch64"]="https://github.com/LoCyan-Team/LoCyanFrpPureApp/releases/download/v0.51.3-9/frp_LoCyanFrp-0.51.3_linux_arm64.tar.gz"
    ["armv7l"]="https://github.com/LoCyan-Team/LoCyanFrpPureApp/releases/download/v0.51.3-9/frp_LoCyanFrp-0.51.3_linux_arm.tar.gz"
    ["i386"]="https://github.com/LoCyan-Team/LoCyanFrpPureApp/releases/download/v0.51.3-9/frp_LoCyanFrp-0.51.3_linux_386.tar.gz"
    ["amd64"]="https://github.com/LoCyan-Team/LoCyanFrpPureApp/releases/download/v0.51.3-9/frp_LoCyanFrp-0.51.3_linux_amd64.tar.gz"
)

confirm() {
    read -p "$1 [Y/n]: " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Nn]$ ]]
}

# -------------------------------
# 系统检测与依赖
# -------------------------------
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGER="apt"
        INSTALL_CMD="sudo apt-get install -y"
    elif command -v yum &> /dev/null; then
        PACKAGE_MANAGER="yum"
        INSTALL_CMD="sudo yum install -y"
    elif command -v dnf &> /dev/null; then
        PACKAGE_MANAGER="dnf"
        INSTALL_CMD="sudo dnf install -y"
    elif command -v pacman &> /dev/null; then
        PACKAGE_MANAGER="pacman"
        INSTALL_CMD="sudo pacman -S --noconfirm"
    elif command -v zypper &> /dev/null; then
        PACKAGE_MANAGER="zypper"
        INSTALL_CMD="sudo zypper install -y"
    elif command -v brew &> /dev/null; then
        PACKAGE_MANAGER="brew"
        INSTALL_CMD="brew install"
    else
        PACKAGE_MANAGER="unknown"
    fi
    info "检测到包管理器: $PACKAGE_MANAGER"
}

install_tool() {
    local tool="$1"
    info "尝试安装: $tool"
    case "$PACKAGE_MANAGER" in
        "apt") sudo apt-get update && sudo apt-get install -y "$tool" ;;
        "yum") sudo yum install -y "$tool" ;;
        "dnf") sudo dnf install -y "$tool" ;;
        "pacman") sudo pacman -S --noconfirm "$tool" ;;
        "zypper") sudo zypper install -y "$tool" ;;
        "brew") brew install "$tool" ;;
        *) error "无法自动安装 $tool，请手动安装" ;;
    esac
}

check_dependencies() {
    info "检查依赖工具..."
    local missing_tools=()
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        missing_tools+=("wget" "curl")
    fi
    if ! command -v tar &> /dev/null; then
        missing_tools+=("tar")
    fi
    if ! command -v unzip &> /dev/null; then
        missing_tools+=("unzip")
    fi

    if [ ${#missing_tools[@]} -eq 0 ]; then
        success "所有依赖工具已安装"
        return
    fi
    warn "缺少: ${missing_tools[*]}"
    detect_package_manager
    if [[ "$PACKAGE_MANAGER" == "unknown" ]]; then
        error "请手动安装: ${missing_tools[*]}"
        exit 1
    fi
    if confirm "是否自动安装缺失工具?"; then
        for tool in "${missing_tools[@]}"; do install_tool "$tool"; done
        success "依赖安装完成"
    else
        error "用户取消安装"; exit 1
    fi
}

# -------------------------------
# 下载和解压
# -------------------------------
download_file() {
    local url="$1"
    local filename="$2"
    info "开始下载: $filename"
    if command -v wget &> /dev/null; then
        wget --progress=bar:force -O "$filename" "$url" || { error "wget 下载失败"; exit 1; }
    elif command -v curl &> /dev/null; then
        curl -L -o "$filename" --progress-bar "$url" || { error "curl 下载失败"; exit 1; }
    else
        error "无下载工具"; exit 1
    fi
    success "下载完成: $filename"
}

extract_archive() {
    local filename="$1"
    info "解压文件: $filename"

    case "$filename" in
        *.tar.gz|*.tgz) tar -xzf "$filename" || { error "解压失败"; exit 1; } ;;
        *.zip) unzip -q "$filename" || { error "解压失败"; exit 1; } ;;
        *) error "不支持的文件格式"; exit 1 ;;
    esac
    success "解压成功"
}

cleanup_archive() {
    local filename="$1"
    if confirm "是否删除压缩文件 $filename?"; then
        rm -f "$filename"
        success "已删除压缩文件"
    else
        info "保留压缩文件"
    fi
}

# -------------------------------
# 主流程
# -------------------------------
main() {
    info "开始系统检测与下载"

    # 获取并规范化架构名（将常见 uname -m 输出映射到 DOWNLOAD_URLS 的 key）
    raw_arch=$(uname -m)
    case "$raw_arch" in
        x86_64|amd64) ARCH="amd64" ;;
        i386|i686) ARCH="i386" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l) ARCH="armv7l" ;;
        *) ARCH="$raw_arch" ;;
    esac
    info "检测到平台架构: $raw_arch -> 使用 key: $ARCH"

    check_dependencies

    local download_url="${DOWNLOAD_URLS[$ARCH]}"
    if [[ -z "$download_url" ]]; then
        error "不支持架构: $ARCH"; exit 1
    fi
    local filename=$(basename "$download_url")

    if confirm "是否开始下载"; then
        download_file "$download_url" "$filename"
        extract_archive "$filename"
        cleanup_archive "$filename"
        info "当前目录内容:"
        ls -la
        success "安装流程完成 ✅"
    else
        info "用户取消下载"; exit 0
    fi
}

main
