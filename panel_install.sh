#!/bin/bash
set -e

# 解决 macOS 下 tr 可能出现的非法字节序列问题
export LANG=en_US.UTF-8
export LC_ALL=C



# 全局下载地址配置
DOCKER_COMPOSEV4_URL="https://github.com/lyqray/flux-panel/releases/download/2.0.6-beta/docker-compose-v4.yml"
DOCKER_COMPOSEV6_URL="https://github.com/lyqray/flux-panel/releases/download/2.0.6-beta/docker-compose-v6.yml"

COUNTRY=$(curl -s https://ipinfo.io/country)
if [ "$COUNTRY" = "CN" ]; then
    # 拼接 URL
    DOCKER_COMPOSEV4_URL="https://ghfast.top/${DOCKER_COMPOSEV4_URL}"
    DOCKER_COMPOSEV6_URL="https://ghfast.top/${DOCKER_COMPOSEV6_URL}"
fi



# 根据IPv6支持情况选择docker-compose URL
get_docker_compose_url() {
  if check_ipv6_support > /dev/null 2>&1; then
    echo "$DOCKER_COMPOSEV6_URL"
  else
    echo "$DOCKER_COMPOSEV4_URL"
  fi
}

# 检查 docker-compose 或 docker compose 命令
check_docker() {
  if command -v docker-compose &> /dev/null; then
    DOCKER_CMD="docker-compose"
  elif command -v docker &> /dev/null; then
    if docker compose version &> /dev/null; then
      DOCKER_CMD="docker compose"
    else
      echo "错误：检测到 docker，但不支持 'docker compose' 命令。请安装 docker-compose 或更新 docker 版本。"
      exit 1
    fi
  else
    echo "错误：未检测到 docker 或 docker-compose 命令。请先安装 Docker。"
    exit 1
  fi
  echo "检测到 Docker 命令：$DOCKER_CMD"
}

# 检测系统是否支持 IPv6
check_ipv6_support() {
  echo "🔍 检测 IPv6 支持..."

  # 检查是否有 IPv6 地址（排除 link-local 地址）
  if ip -6 addr show | grep -v "scope link" | grep -q "inet6"; then
    echo "✅ 检测到系统支持 IPv6"
    return 0
  elif ifconfig 2>/dev/null | grep -v "fe80:" | grep -q "inet6"; then
    echo "✅ 检测到系统支持 IPv6"
    return 0
  else
    echo "⚠️ 未检测到 IPv6 支持"
    return 1
  fi
}



# 配置 Docker 启用 IPv6
configure_docker_ipv6() {
  echo "🔧 配置 Docker IPv6 支持..."

  # 检查操作系统类型
  OS_TYPE=$(uname -s)

  if [[ "$OS_TYPE" == "Darwin" ]]; then
    # macOS 上 Docker Desktop 已默认支持 IPv6
    echo "✅ macOS Docker Desktop 默认支持 IPv6"
    return 0
  fi

  # Docker daemon 配置文件路径
  DOCKER_CONFIG="/etc/docker/daemon.json"

  # 检查是否需要 sudo
  if [[ $EUID -ne 0 ]]; then
    SUDO_CMD="sudo"
  else
    SUDO_CMD=""
  fi

  # 检查 Docker 配置文件
  if [ -f "$DOCKER_CONFIG" ]; then
    # 检查是否已经配置了 IPv6
    if grep -q '"ipv6"' "$DOCKER_CONFIG"; then
      echo "✅ Docker 已配置 IPv6 支持"
    else
      echo "📝 更新 Docker 配置以启用 IPv6..."
      # 备份原配置
      $SUDO_CMD cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.backup"

      # 使用 jq 或 sed 添加 IPv6 配置
      if command -v jq &> /dev/null; then
        $SUDO_CMD jq '. + {"ipv6": true, "fixed-cidr-v6": "fd72::/80"}' "$DOCKER_CONFIG" > /tmp/daemon.json && $SUDO_CMD mv /tmp/daemon.json "$DOCKER_CONFIG"
      else
        # 如果没有 jq，使用 sed
        $SUDO_CMD sed -i 's/^{$/{\n  "ipv6": true,\n  "fixed-cidr-v6": "fd72::\/80",/' "$DOCKER_CONFIG"
      fi

      echo "🔄 重启 Docker 服务..."
      if command -v systemctl &> /dev/null; then
        $SUDO_CMD systemctl restart docker
      elif command -v service &> /dev/null; then
        $SUDO_CMD service docker restart
      else
        echo "⚠️ 请手动重启 Docker 服务"
      fi
      sleep 5
    fi
  else
    # 创建新的配置文件
    echo "📝 创建 Docker 配置文件..."
    $SUDO_CMD mkdir -p /etc/docker
    echo '{
  "ipv6": true,
  "fixed-cidr-v6": "fd72::/80"
}' | $SUDO_CMD tee "$DOCKER_CONFIG" > /dev/null

    echo "🔄 重启 Docker 服务..."
    if command -v systemctl &> /dev/null; then
      $SUDO_CMD systemctl restart docker
    elif command -v service &> /dev/null; then
      $SUDO_CMD service docker restart
    else
      echo "⚠️ 请手动重启 Docker 服务"
    fi
    sleep 5
  fi
}

# 显示菜单
show_menu() {
  echo "==============================================="
  echo "          面板管理脚本"
  echo "==============================================="
  echo "请选择操作："
  echo "1. 安装面板"
  echo "2. 更新面板"
  echo "3. 卸载面板"
  echo "4. 导出备份"
  echo "5. 导入备份（覆盖现有数据，谨慎操作）"
  echo "6. 退出"
  echo "==============================================="
}

generate_random() {
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c16
}

# 删除脚本自身
delete_self() {
  echo ""
  echo "🗑️ 操作已完成，正在清理脚本文件..."
  SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
  sleep 1
  rm -f "$SCRIPT_PATH" && echo "✅ 脚本文件已删除" || echo "❌ 删除脚本文件失败"
}



# 获取用户输入的配置参数
get_config_params() {
  echo "🔧 请输入配置参数："

  read -p "前端端口（默认 6366）: " FRONTEND_PORT
  FRONTEND_PORT=${FRONTEND_PORT:-6366}

  read -p "后端端口（默认 6365）: " BACKEND_PORT
  BACKEND_PORT=${BACKEND_PORT:-6365}

  # 生成JWT密钥
  JWT_SECRET=$(generate_random)
}

# 安装功能
install_panel() {
  echo "🚀 开始安装面板..."
  check_docker
  get_config_params

  echo "🔽 下载必要文件..."
  DOCKER_COMPOSE_URL=$(get_docker_compose_url)
  echo "📡 选择配置文件：$(basename "$DOCKER_COMPOSE_URL")"
  curl -L -o docker-compose.yml "$DOCKER_COMPOSE_URL"
  echo "✅ 文件准备完成"

  # 自动检测并配置 IPv6 支持
  if check_ipv6_support; then
    echo "🚀 系统支持 IPv6，自动启用 IPv6 配置..."
    configure_docker_ipv6
  fi

  cat > .env <<EOF
JWT_SECRET=$JWT_SECRET
FRONTEND_PORT=$FRONTEND_PORT
BACKEND_PORT=$BACKEND_PORT
EOF

  echo "🚀 启动 docker 服务..."
  $DOCKER_CMD up -d

  echo "🎉 部署完成"
  echo "🌐 访问地址: http://服务器IP:$FRONTEND_PORT"
  echo "📖 部署完成后请阅读下使用文档，求求了啊，不要上去就是一顿操作"
  echo "📚 文档地址: https://tes.cc/guide.html"
  echo "💡 默认管理员账号: admin_user / admin_user"
  echo "⚠️  登录后请立即修改默认密码！"


}

# 更新功能
update_panel() {
  echo "🔄 开始更新面板..."
  check_docker

  echo "🔽 下载最新配置文件..."
  DOCKER_COMPOSE_URL=$(get_docker_compose_url)
  echo "📡 选择配置文件：$(basename "$DOCKER_COMPOSE_URL")"
  curl -L -o docker-compose.yml "$DOCKER_COMPOSE_URL"
  echo "✅ 下载完成"

  # 自动检测并配置 IPv6 支持
  if check_ipv6_support; then
    echo "🚀 系统支持 IPv6，自动启用 IPv6 配置..."
    configure_docker_ipv6
  fi

  # 先发送 SIGTERM 信号，让应用优雅关闭
  docker stop -t 30 springboot-backend 2>/dev/null || true
  docker stop -t 10 vite-frontend 2>/dev/null || true
  
  # 等待 WAL 文件同步
  echo "⏳ 等待数据同步..."
  sleep 5
  
  # 然后再完全停止
  $DOCKER_CMD down

  echo "⬇️ 拉取最新镜像..."
  $DOCKER_CMD pull

  echo "🚀 启动更新后的服务..."
  $DOCKER_CMD up -d

  # 等待服务启动
  echo "⏳ 等待服务启动..."

  # 检查后端容器健康状态
  echo "🔍 检查后端服务状态..."
  for i in {1..90}; do
    if docker ps --format "{{.Names}}" | grep -q "^springboot-backend$"; then
      BACKEND_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' springboot-backend 2>/dev/null || echo "unknown")
      if [[ "$BACKEND_HEALTH" == "healthy" ]]; then
        echo "✅ 后端服务健康检查通过"
        break
      elif [[ "$BACKEND_HEALTH" == "starting" ]]; then
        # 继续等待
        :
      elif [[ "$BACKEND_HEALTH" == "unhealthy" ]]; then
        echo "⚠️ 后端健康状态：$BACKEND_HEALTH"
      fi
    else
      echo "⚠️ 后端容器未找到或未运行"
      BACKEND_HEALTH="not_running"
    fi
    if [ $i -eq 90 ]; then
      echo "❌ 后端服务启动超时（90秒）"
      echo "🔍 当前状态：$(docker inspect -f '{{.State.Health.Status}}' springboot-backend 2>/dev/null || echo '容器不存在')"
      echo "🛑 更新终止"
      return 1
    fi
    # 每15秒显示一次进度
    if [ $((i % 15)) -eq 1 ]; then
      echo "⏳ 等待后端服务启动... ($i/90) 状态：${BACKEND_HEALTH:-unknown}"
    fi
    sleep 1
  done

  echo "✅ 更新完成"
}



# 卸载功能
uninstall_panel() {
  echo "🗑️ 开始卸载面板..."
  check_docker

  if [[ ! -f "docker-compose.yml" ]]; then
    echo "⚠️ 未找到 docker-compose.yml 文件，正在下载以完成卸载..."
    DOCKER_COMPOSE_URL=$(get_docker_compose_url)
    echo "📡 选择配置文件：$(basename "$DOCKER_COMPOSE_URL")"
    curl -L -o docker-compose.yml "$DOCKER_COMPOSE_URL"
    echo "✅ docker-compose.yml 下载完成"
  fi

  read -p "确认卸载面板吗？此操作将停止并删除所有容器和数据 (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ 取消卸载"
    return 0
  fi

  echo "🛑 停止并删除容器、镜像、卷..."
  $DOCKER_CMD down --rmi all --volumes --remove-orphans
  echo "🧹 删除配置文件..."
  rm -f docker-compose.yml .env
  echo "✅ 卸载完成"
}



# 导出数据库备份
export_migration_sql() {
  echo "📄 开始导出 SQLite 数据库备份..."

  # 检查后端容器是否运行
  if ! docker ps --format "{{.Names}}" | grep -q "^springboot-backend$"; then
    echo "❌ 后端容器未运行，无法备份数据库"
    echo "🔍 当前运行的容器："
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    return 1
  fi

  # 检查数据库文件是否存在
  if ! docker exec springboot-backend ls /app/data/gost.db > /dev/null 2>&1; then
    echo "❌ 数据库文件 /app/data/gost.db 不存在"
    return 1
  fi

  # 生成备份文件名
  BACKUP_FILE="gost_backup_$(date +%Y%m%d_%H%M%S).db"
  
  echo "⏳ 正在备份数据库..."
  
  # 使用 docker cp 命令复制数据库文件
  if docker cp springboot-backend:/app/data/gost.db "./$BACKUP_FILE"; then
    echo "✅ 数据库备份成功"
    
    # 检查文件大小
    if [[ -f "$BACKUP_FILE" ]] && [[ -s "$BACKUP_FILE" ]]; then
      FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
      echo "📁 文件位置: $(pwd)/$BACKUP_FILE"
      echo "📊 文件大小: $FILE_SIZE"
      
      # 验证 SQLite 文件完整性（可选）
      if command -v sqlite3 &> /dev/null; then
        if sqlite3 "$BACKUP_FILE" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
          echo "✅ 数据库文件完整性验证通过"
        else
          echo "⚠️ 数据库文件完整性验证失败，但备份文件已生成"
        fi
      else
        echo "ℹ️ 未安装 sqlite3 工具，跳过完整性验证"
      fi
    else
      echo "❌ 备份文件为空或不存在"
      return 1
    fi
  else
    echo "❌ 数据库备份失败"
    return 1
  fi
}



# 导入数据库备份
import_backup() {
  echo "🔄 开始导入数据库备份（覆盖现有数据）"
  echo "⚠️  警告：此操作将覆盖现有数据库，且不可恢复！"

  # 检查后端容器是否运行
  if ! docker ps --format "{{.Names}}" | grep -q "^springboot-backend$"; then
    echo "❌ 后端容器未运行，无法导入备份"
    echo "🔍 当前运行的容器："
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    return 1
  fi

  # 列出当前目录下的备份文件
  echo "📁 当前目录下的备份文件："
  local backup_files=($(ls -1 *.db 2>/dev/null | grep -E "gost_backup_.*\.db$" | head -10))
  
  if [[ ${#backup_files[@]} -eq 0 ]]; then
    echo "❌ 未找到备份文件（文件名格式：gost_backup_年月日_时分秒.db）"
    echo "💡 请先将备份文件放在当前目录下"
    return 1
  fi

  # 显示备份文件列表
  echo "==============================================="
  echo "           可用的备份文件"
  echo "==============================================="
  for i in "${!backup_files[@]}"; do
    local file_size=$(du -h "${backup_files[$i]}" | cut -f1)
    local file_date=$(stat -c %y "${backup_files[$i]}" 2>/dev/null || stat -f "%Sm" "${backup_files[$i]}" 2>/dev/null || echo "未知时间")
    echo "$((i+1)). ${backup_files[$i]} ($file_size) - $file_date"
  done
  echo "==============================================="

  # 选择备份文件
  read -p "请选择要导入的备份文件编号 (1-${#backup_files[@]}): " file_choice
  
  if ! [[ "$file_choice" =~ ^[0-9]+$ ]] || [[ "$file_choice" -lt 1 ]] || [[ "$file_choice" -gt ${#backup_files[@]} ]]; then
    echo "❌ 无效的选择"
    return 1
  fi

  local selected_file="${backup_files[$((file_choice-1))]}"
  
  # 确认操作
  echo ""
  echo "⚠️  即将导入备份文件: $selected_file"
  echo "⚠️  此操作将："
  echo "    - 停止后端服务"
  echo "    - 覆盖现有数据库"
  echo "    - 重启后端服务"
  echo ""
  read -p "确认执行此危险操作吗？请输入 'CONFIRM' 继续: " confirm_input
  
  if [[ "$confirm_input" != "CONFIRM" ]]; then
    echo "❌ 操作已取消"
    return 0
  fi

  echo "⏳ 开始导入备份..."

  # 停止后端服务
  echo "🛑 停止后端服务..."
  if ! docker stop springboot-backend > /dev/null 2>&1; then
    echo "❌ 停止后端服务失败"
    return 1
  fi

  # 备份当前数据库（可选）
  echo "📦 备份当前数据库..."
  local current_backup="current_db_backup_$(date +%Y%m%d_%H%M%S).db"
  if docker cp springboot-backend:/app/data/gost.db "./$current_backup" 2>/dev/null; then
    echo "✅ 当前数据库已备份为: $current_backup"
  else
    echo "⚠️ 当前数据库备份失败，继续执行导入..."
  fi

  # 导入备份文件
  echo "⬆️ 导入备份文件: $selected_file"
  if docker cp "./$selected_file" springboot-backend:/app/data/gost.db; then
    echo "✅ 备份文件导入成功"
    
    # 设置正确的文件权限
    docker exec springboot-backend chmod 644 /app/data/gost.db 2>/dev/null || true
    
    # 验证导入的数据库
    echo "🔍 验证导入的数据库..."
    if docker exec springboot-backend ls -la /app/data/gost.db > /dev/null 2>&1; then
      echo "✅ 数据库文件验证通过"
    else
      echo "❌ 数据库文件验证失败"
    fi
  else
    echo "❌ 备份文件导入失败"
    # 尝试恢复服务
    docker start springboot-backend > /dev/null 2>&1 || true
    return 1
  fi

  # 重启后端服务
  echo "🚀 重启后端服务..."
  if docker start springboot-backend > /dev/null 2>&1; then
    echo "✅ 后端服务启动成功"
    
    # 等待服务健康检查
    echo "⏳ 等待服务就绪..."
    for i in {1..30}; do
      local health_status=$(docker inspect -f '{{.State.Health.Status}}' springboot-backend 2>/dev/null || echo "unknown")
      if [[ "$health_status" == "healthy" ]]; then
        echo "✅ 后端服务健康检查通过"
        break
      elif [[ $i -eq 30 ]]; then
        echo "⚠️ 后端服务启动超时，但已运行"
      fi
      sleep 2
    done
  else
    echo "❌ 后端服务启动失败"
    return 1
  fi

  echo "🎉 数据库导入完成"
  echo "💡 如果遇到问题，可以使用之前自动备份的文件恢复: $current_backup"
}



# 主逻辑
main() {

  # 显示交互式菜单
  while true; do
    show_menu
    read -p "请输入选项 (1-5): " choice

    case $choice in
      1)
        install_panel
        delete_self
        exit 0
        ;;
      2)
        update_panel
        delete_self
        exit 0
        ;;
      3)
        uninstall_panel
        delete_self
        exit 0
        ;;
      4)
        export_migration_sql
        delete_self
        exit 0
        ;;
      5)
        import_backup
        delete_self
        exit 0
        ;;
      6)
        echo "👋 退出脚本"
        delete_self
        exit 0
        ;;
      *)
        echo "❌ 无效选项，请输入 1-5"
        echo ""
        ;;
    esac
  done
}

# 执行主函数
main
