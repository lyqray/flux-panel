#!/bin/bash

# 配置路径
INSTALL_DIR="/etc/flux_gost2"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"

# --- 全局环境检查 ---
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "❌ 未检测到 Docker，请先安装 Docker。"
        exit 1
    fi
    if docker compose version &> /dev/null; then
        DOCKER_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_CMD="docker-compose"
    else
        echo "❌ 未检测到 Docker Compose 插件。"
        exit 1
    fi
}

check_docker

# 获取系统架构
get_architecture() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "amd64" ;;
    esac
}

# 构建下载地址
build_download_url() {
    local ARCH=$(get_architecture)
    echo "https://github.com/lyqray/flux-panel/releases/download/1.4.3C/gost-${ARCH}"
}

DOWNLOAD_URL=$(build_download_url)
COUNTRY=$(curl -s --connect-timeout 5 https://ipinfo.io/country)
if [ "$COUNTRY" = "CN" ]; then
    DOWNLOAD_URL="https://ghfast.top/${DOWNLOAD_URL}"
fi

# 删除脚本自身
delete_self() {
  echo ""
  echo "🗑️ 操作已完成，正在清理脚本文件..."
  SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
  sleep 1
  if [ -f "$SCRIPT_PATH" ]; then
    rm -f "$SCRIPT_PATH" && echo "✅ 脚本文件已删除"
  else
    echo "ℹ️ 脚本已清理。"
  fi
}

# 获取配置参数
get_config_params() {
  if [[ -z "$SERVER_ADDR" || -z "$SECRET" ]]; then
    echo "请输入面板连接信息："
    read -p "服务器地址 (addr): " SERVER_ADDR
    read -p "密钥 (secret): " SECRET
    if [[ -z "$SERVER_ADDR" || -z "$SECRET" ]]; then
      echo "❌ 参数不完整，操作取消。"
      exit 1
    fi
  fi
}

# 1. 安装功能
install_flux_gost2() {
  echo "🚀 开始安装 Flux-Gost2 (Docker)..."
  get_config_params
  
  # 停止可能存在的旧容器，防止 Text file busy
  if [ -d "$INSTALL_DIR" ] && [ -f "$COMPOSE_FILE" ]; then
    cd "$INSTALL_DIR" && $DOCKER_CMD down 2>/dev/null
  fi

  mkdir -p "$INSTALL_DIR"
  echo "⬇️ 下载执行文件..."
  curl -L "$DOWNLOAD_URL" -o "$INSTALL_DIR/flux_gost2"
  if [[ ! -s "$INSTALL_DIR/flux_gost2" ]]; then
    echo "❌ 下载失败。"
    exit 1
  fi
  chmod +x "$INSTALL_DIR/flux_gost2"

  cat > "$INSTALL_DIR/config.json" <<EOF
{
  "addr": "$SERVER_ADDR",
  "secret": "$SECRET"
}
EOF

  if [[ ! -f "$INSTALL_DIR/gost.json" ]]; then echo "{}" > "$INSTALL_DIR/gost.json"; fi

  cat > "$COMPOSE_FILE" <<EOF
services:
  flux_gost2:
    image: alpine:3.23
    # image: debian:bookworm-slim
    container_name: flux_gost2
    restart: unless-stopped
    network_mode: host
    ulimits:  # 放宽高并发数限制
      nofile:
        soft: 1048576
        hard: 1048576
      nproc:
        soft: 1048576
        hard: 1048576
    working_dir: /etc/gost
    volumes:
      - ./:/etc/gost
    command: ["/etc/gost/flux_gost2", "-C", "/etc/gost/config.json", "-C", "/etc/gost/gost.json"]
EOF

  cd "$INSTALL_DIR" && $DOCKER_CMD up -d
  echo "✅ 安装成功！"
}

# 2. 更新功能 (仅更新二进制文件并重启)
update_flux_gost2() {
  echo "🔄 正在更新 flux_gost2 二进制文件..."
  if [ ! -d "$INSTALL_DIR" ] || [ ! -f "$COMPOSE_FILE" ]; then
    echo "❌ 未检测到已安装的服务，请先选择 1 进行安装。"
    return 1
  fi

  # 必须先停掉容器，否则无法覆盖二进制文件 (Text file busy)
  echo "🛑 停止当前容器..."
  cd "$INSTALL_DIR" && $DOCKER_CMD stop flux_gost2 2>/dev/null

  echo "⬇️ 下载最新二进制文件..."
  curl -L "$DOWNLOAD_URL" -o "$INSTALL_DIR/flux_gost2"
  if [[ ! -s "$INSTALL_DIR/flux_gost2" ]]; then
    echo "❌ 下载失败。"
    $DOCKER_CMD start flux_gost2 # 失败了要把旧的拉起来
    exit 1
  fi
  chmod +x "$INSTALL_DIR/flux_gost2"

  echo "🚀 重启容器..."
  $DOCKER_CMD up -d
  echo "✅ 更新完成！"
}

# 3. 卸载功能
uninstall_flux_gost2() {
  echo "🗑️ 正在卸载..."
  if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR" && $DOCKER_CMD down
    rm -rf "$INSTALL_DIR"
    echo "✅ 卸载完成。"
  else
    echo "❌ 未发现安装目录。"
  fi
}

# 解析命令行参数
while getopts "a:s:" opt; do
  case $opt in
    a) SERVER_ADDR="$OPTARG" ;;
    s) SECRET="$OPTARG" ;;
  esac
done

# 主菜单逻辑
main() {
  if [[ -n "$SERVER_ADDR" && -n "$SECRET" ]]; then
    install_flux_gost2
    delete_self
    exit 0
  fi

  while true; do
    echo "==============================================="
    echo "        Flux-Gost2 管理脚本 (Docker版)"
    echo "==============================================="
    echo "1. 安装"
    echo "2. 更新"
    echo "3. 卸载"
    echo "4. 退出"
    echo "==============================================="
    read -p "请输入选项 (1-4): " choice

    case $choice in
      1)
        install_flux_gost2
        delete_self
        exit 0
        ;;
      2)
        update_flux_gost2
        delete_self
        exit 0
        ;;
      3)
        uninstall_flux_gost2
        delete_self
        exit 0
        ;;
      4)
        echo "👋 退出脚本"
        exit 0
        ;;
      *)
        echo "❌ 无效选项"
        ;;
    esac
  done
}

main
