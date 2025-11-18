#!/bin/bash

# ===============================
# LoCyanFrp 自动安装脚本（增强版）
# 功能：下载 -> 校验 -> 解压 -> 安装 -> 清理
# ===============================

# 作者：热冰块hic，chatGPT
# 版本：2.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 日志函数
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }

# 配置变量
SCRIPT_VERSION="2.0"
DEFAULT_INSTALL_DIR="$HOME/locyanfrp"
GITHUB_API_URL="https://api.github.com/repos/LoCyan-Team/LoCyanFrpPureApp/releases/latest"

# 下载地址配置（作为后备）
declare -A DOWNLOAD_URLS=(
    ["aarch64"]="https://github.com/LoCyan-Team/LoCyanFrpPureApp/releases/download/v0.51.3-9/frp_LoCyanFrp-0.51.3_linux_arm64.tar.gz"
    ["armv7l"]="https://github.com/LoCyan-Team/LoCyanFrpPureApp/releases/download/v0.51.3-9/frp_LoCyanFrp-0.51.3_linux_arm.tar.gz"
    ["i386"]="https://github.com/LoCyan-Team/LoCyanFrpPureApp/releases/download/v0.51.3-9/frp_LoCyanFrp-0.51.3_linux_386.tar.gz"
    ["amd64"]="https://github.com/LoCyan-Team/LoCyanFrpPureApp/releases/download/v0.51.3-9/frp_LoCyanFrp-0.51.3_linux_amd64.tar.gz"
)

# 信号处理
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        warn "脚本执行失败，执行清理..."
        [[ -f "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
        [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    fi
}
trap cleanup_on_exit EXIT

# -------------------------------
# 工具函数
# -------------------------------
print_banner() {
    echo -e "${BOLD}${CYAN}"
    echo "=========================================="
    echo "    LoCyanFrp 自动安装脚本 v$SCRIPT_VERSION"
    echo "=========================================="
    echo -e "${NC}"
}

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local reply
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi
    
    while true; do
        read -p "$prompt" -r reply
        case "${reply:-$default}" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo "请输入 y 或 n";;
        esac
    done
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# -------------------------------
# 系统检测与依赖
# -------------------------------
detect_system() {
    info "检测系统环境..."
    
    # 检测架构
    RAW_ARCH=$(uname -m)
    case "$RAW_ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        i386|i686) ARCH="i386" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l) ARCH="armv7l" ;;
        *) ARCH="$RAW_ARCH" ;;
    esac
    info "系统架构: $RAW_ARCH -> $ARCH"
    
    # 检测操作系统
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        info "操作系统: $NAME $VERSION"
    else
        warn "无法检测具体操作系统"
    fi
}

detect_package_manager() {
    local managers=(
        "apt:Debian/Ubuntu"
        "yum:RHEL/CentOS"
        "dnf:Fedora/RHEL"
        "pacman:Arch Linux"
        "zypper:openSUSE"
        "brew:macOS"
    )
    
    for manager_info in "${managers[@]}"; do
        local manager="${manager_info%%:*}"
        if command_exists "$manager"; then
            PACKAGE_MANAGER="$manager"
            info "检测到包管理器: $manager"
            return 0
        fi
    done
    
    PACKAGE_MANAGER="unknown"
    warn "未检测到支持的包管理器"
}

install_tool() {
    local tool="$1"
    info "安装: $tool"
    
    case "$PACKAGE_MANAGER" in
        "apt") sudo apt-get update -qq && sudo apt-get install -y "$tool" ;;
        "yum") sudo yum install -y "$tool" ;;
        "dnf") sudo dnf install -y "$tool" ;;
        "pacman") sudo pacman -S --noconfirm "$tool" ;;
        "zypper") sudo zypper install -y "$tool" ;;
        "brew") brew install "$tool" ;;
        *) 
            error "无法自动安装 $tool，请手动安装后重新运行脚本"
            return 1
            ;;
    esac
}

check_dependencies() {
    info "检查系统依赖..."
    local missing_tools=()
    
    # 检查下载工具
    if ! command_exists wget && ! command_exists curl; then
        missing_tools+=("wget")
    fi
    
    # 检查解压工具
    if ! command_exists tar; then
        missing_tools+=("tar")
    fi
    
    if ! command_exists unzip; then
        missing_tools+=("unzip")
    fi
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        success "所有依赖工具已安装"
        return 0
    fi
    
    warn "缺少依赖: ${missing_tools[*]}"
    
    if [[ "$PACKAGE_MANAGER" == "unknown" ]]; then
        error "请手动安装以下工具: ${missing_tools[*]}"
        return 1
    fi
    
    if confirm "是否自动安装缺失的依赖？"; then
        for tool in "${missing_tools[@]}"; do
            install_tool "$tool" || return 1
        done
        success "依赖安装完成"
    else
        error "用户取消安装，脚本退出"
        return 1
    fi
}

# -------------------------------
# 版本检测与下载
# -------------------------------
get_latest_version() {
    info "获取最新版本信息..."
    
    if ! command_exists jq; then
        warn "未找到 jq 命令，使用默认版本"
        echo "v0.51.3-9"
        return 0
    fi
    
    local api_response
    if command_exists curl; then
        api_response=$(curl -sL "$GITHUB_API_URL" 2>/dev/null)
    elif command_exists wget; then
        api_response=$(wget -qO- "$GITHUB_API_URL" 2>/dev/null)
    fi
    
    if [[ -n "$api_response" ]]; then
        local latest_version
        latest_version=$(echo "$api_response" | jq -r '.tag_name // empty')
        if [[ -n "$latest_version" ]]; then
            success "检测到最新版本: $latest_version"
            echo "$latest_version"
            return 0
        fi
    fi
    
    warn "无法获取最新版本，使用默认版本"
    echo "v0.51.3-9"
}

get_download_url() {
    local version="$1"
    local arch="$2"
    
    # 尝试从 GitHub API 获取下载链接
    if command_exists jq; then
        local api_response
        if command_exists curl; then
            api_response=$(curl -sL "$GITHUB_API_URL" 2>/dev/null)
        elif command_exists wget; then
            api_response=$(wget -qO- "$GITHUB_API_URL" 2>/dev/null)
        fi
        
        if [[ -n "$api_response" ]]; then
            local asset_url
            case "$arch" in
                "amd64") asset_url=$(echo "$api_response" | jq -r '.assets[] | select(.name | contains("amd64")) | .browser_download_url // empty') ;;
                "i386") asset_url=$(echo "$api_response" | jq -r '.assets[] | select(.name | contains("386")) | .browser_download_url // empty') ;;
                "aarch64") asset_url=$(echo "$api_response" | jq -r '.assets[] | select(.name | contains("arm64")) | .browser_download_url // empty') ;;
                "armv7l") asset_url=$(echo "$api_response" | jq -r '.assets[] | select(.name | contains("arm")) | .browser_download_url // empty') ;;
            esac
            
            if [[ -n "$asset_url" ]]; then
                echo "$asset_url"
                return 0
            fi
        fi
    fi
    
    # 使用后备下载链接
    warn "使用后备下载链接"
    echo "${DOWNLOAD_URLS[$arch]}"
}

download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        info "下载尝试 $attempt/$max_attempts: $(basename "$output")"
        
        if command_exists wget; then
            if wget --progress=bar:force -O "$output" "$url"; then
                return 0
            fi
        elif command_exists curl; then
            if curl -L -o "$output" --progress-bar "$url"; then
                return 0
            fi
        fi
        
        warn "下载失败，尝试 $attempt/$max_attempts"
        [[ $attempt -lt $max_attempts ]] && sleep 5
        ((attempt++))
    done
    
    error "下载失败: $url"
    return 1
}

verify_download() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        error "文件不存在: $file"
        return 1
    fi
    
    local file_size
    if command_exists stat; then
        file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    else
        file_size=$(wc -c < "$file" 2>/dev/null)
    fi
    
    if [[ $file_size -eq 0 ]]; then
        error "下载文件为空: $file"
        return 1
    fi
    
    # 转换为人类可读格式
    local size_human
    if command_exists numfmt; then
        size_human=$(numfmt --to=iec "$file_size")
    else
        size_human="${file_size} bytes"
    fi
    
    success "文件校验通过: $(basename "$file") ($size_human)"
    return 0
}

# -------------------------------
# 安装流程
# -------------------------------
select_install_dir() {
    if confirm "是否使用默认安装目录 ($DEFAULT_INSTALL_DIR)？" "y"; then
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    else
        read -rp "请输入安装目录路径: " custom_dir
        INSTALL_DIR="${custom_dir:-$DEFAULT_INSTALL_DIR}"
    fi
    
    # 确保路径是绝对路径
    if [[ "$INSTALL_DIR" != /* ]]; then
        INSTALL_DIR="$(pwd)/$INSTALL_DIR"
    fi
    
    info "安装目录: $INSTALL_DIR"
}

create_install_dir() {
    if [[ -d "$INSTALL_DIR" ]]; then
        if confirm "目录 $INSTALL_DIR 已存在，是否删除重新安装？"; then
            rm -rf "$INSTALL_DIR"
        else
            if confirm "是否保留现有文件并继续安装？"; then
                info "在现有目录中继续安装"
            else
                error "安装取消"
                return 1
            fi
        fi
    fi
    
    mkdir -p "$INSTALL_DIR" || {
        error "无法创建安装目录: $INSTALL_DIR"
        return 1
    }
    success "创建安装目录: $INSTALL_DIR"
}

extract_archive() {
    local filename="$1"
    local target_dir="$2"
    
    info "解压文件: $(basename "$filename")"
    
    case "$filename" in
        *.tar.gz|*.tgz)
            if ! tar -xzf "$filename" -C "$target_dir"; then
                error "tar 解压失败"
                return 1
            fi
            ;;
        *.zip)
            if ! unzip -q "$filename" -d "$target_dir"; then
                error "unzip 解压失败"
                return 1
            fi
            ;;
        *)
            error "不支持的文件格式: $filename"
            return 1
            ;;
    esac
    
    success "解压完成"
}

setup_permissions() {
    local target_dir="$1"
    
    info "设置文件权限..."
    
    # 查找可执行文件并设置权限
    find "$target_dir" -type f -name "frpc" -o -name "frps" -o -name "*.sh" | while read -r file; do
        if [[ -f "$file" ]]; then
            chmod +x "$file" && debug "设置可执行: $(basename "$file")"
        fi
    done
    
    success "权限设置完成"
}

create_symlink() {
    local target_dir="$1"
    
    if confirm "是否创建符号链接到 /usr/local/bin（需要sudo权限）？"; then
        local binary
        binary=$(find "$target_dir" -name "frpc" -type f | head -n1)
        
        if [[ -n "$binary" && -f "$binary" ]]; then
            sudo ln -sf "$binary" /usr/local/bin/frpc
            success "创建符号链接: /usr/local/bin/frpc -> $binary"
        else
            warn "未找到 frpc 可执行文件，跳过符号链接创建"
        fi
    fi
}

cleanup_installation() {
    local filename="$1"
    
    if confirm "安装完成后是否删除压缩文件？"; then
        rm -f "$filename"
        success "已删除压缩文件"
    else
        info "保留压缩文件: $filename"
    fi
}

show_installation_info() {
    local install_dir="$1"
    
    success "LoCyanFrp 安装完成！"
    echo
    echo -e "${BOLD}安装信息:${NC}"
    echo -e "  安装目录: ${CYAN}$install_dir${NC}"
    echo
    echo -e "${BOLD}下一步操作:${NC}"
    echo -e "  1. 进入安装目录: ${CYAN}cd $install_dir${NC}"
    echo -e "  2. 查看文件列表: ${CYAN}ls -la${NC}"
    echo -e "  3. 运行 frpc: ${CYAN}./frpc -h${NC}"
    echo
    echo -e "更多帮助请参考: ${CYAN}https://github.com/LoCyan-Team/LoCyanFrpPureApp${NC}"
}

# -------------------------------
# 主流程
# -------------------------------
main() {
    print_banner
    detect_system
    detect_package_manager
    
    # 检查依赖
    if ! check_dependencies; then
        exit 1
    fi
    
    # 获取版本信息
    LATEST_VERSION=$(get_latest_version)
    info "使用版本: $LATEST_VERSION"
    
    # 选择安装目录
    select_install_dir
    
    # 创建安装目录
    if ! create_install_dir; then
        exit 1
    fi
    
    # 获取下载链接
    DOWNLOAD_URL=$(get_download_url "$LATEST_VERSION" "$ARCH")
    if [[ -z "$DOWNLOAD_URL" ]]; then
        error "不支持的架构: $ARCH"
        exit 1
    fi
    
    local filename
    filename=$(basename "$DOWNLOAD_URL")
    local temp_file="/tmp/$filename"
    
    info "开始下载 LoCyanFrp"
    info "下载链接: $DOWNLOAD_URL"
    
    # 下载文件
    if ! download_with_retry "$DOWNLOAD_URL" "$temp_file"; then
        exit 1
    fi
    
    # 验证下载
    if ! verify_download "$temp_file"; then
        exit 1
    fi
    
    # 解压文件
    if ! extract_archive "$temp_file" "$INSTALL_DIR"; then
        exit 1
    fi
    
    # 设置权限
    setup_permissions "$INSTALL_DIR"
    
    # 创建符号链接（可选）
    create_symlink "$INSTALL_DIR"
    
    # 清理
    cleanup_installation "$temp_file"
    
    # 显示安装信息
    show_installation_info "$INSTALL_DIR"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
