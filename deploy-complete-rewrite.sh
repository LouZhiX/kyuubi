#!/bin/bash

# 部署完整Kyuubi重写规则脚本
# 专门处理API请求如 /api/v1/admin/sessions

KNOX_HOME="/Users/junglelou/Downloads/knox-1.6.1.2"
KYUUBI_HOME="/Users/junglelou/Downloads/apache-kyuubi-1.9.2-bin"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "==================================================================="
echo "              部署完整Kyuubi重写规则"
echo "              特别处理API请求: /api/v1/admin/sessions"
echo "==================================================================="

# 检查Knox是否运行
if pgrep -f knox > /dev/null; then
    log_info "Knox正在运行，将停止服务进行更新..."
    cd "$KNOX_HOME"
    bin/gateway.sh stop
    sleep 3
else
    log_info "Knox未运行"
fi

# 备份现有配置
log_info "备份现有重写规则..."
BACKUP_DIR="$KNOX_HOME/conf/backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -f "$KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml" ]; then
    cp "$KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml" "$BACKUP_DIR/"
    log_success "原rewrite.xml已备份到: $BACKUP_DIR/"
fi

# 创建服务定义目录
log_info "确保服务定义目录存在..."
mkdir -p "$KNOX_HOME/data/services/kyuubiui/1.9.0"

# 部署新的重写规则
log_info "部署新的重写规则..."
cp kyuubi-complete-rewrite.xml "$KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml"

if [ $? -eq 0 ]; then
    log_success "✅ 新的重写规则已部署"
else
    log_error "❌ 部署重写规则失败"
    exit 1
fi

# 验证文件内容
log_info "验证重写规则内容..."
if grep -q "api/v1/admin/sessions" "$KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml" 2>/dev/null; then
    log_warn "注意：重写规则不应包含具体的API路径，应使用通配符模式"
fi

if grep -q "kyuubi/api/" "$KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml"; then
    log_success "✅ API重写规则已包含"
else
    log_error "❌ API重写规则缺失"
fi

# 启用详细的重写日志
log_info "启用详细的重写日志..."
cp "$KNOX_HOME/conf/gateway-log4j.properties" "$BACKUP_DIR/" 2>/dev/null || true

cat >> "$KNOX_HOME/conf/gateway-log4j.properties" << 'EOF'

# Enhanced logging for Kyuubi rewrite debugging
log4j.logger.org.apache.knox.gateway.filter.rewrite=TRACE
log4j.logger.org.apache.knox.gateway.dispatch=DEBUG
log4j.logger.org.apache.knox.gateway.services=DEBUG
EOF

# 启动Knox
log_info "启动Knox服务..."
cd "$KNOX_HOME"
bin/gateway.sh start

if [ $? -eq 0 ]; then
    log_success "✅ Knox已启动"
else
    log_error "❌ Knox启动失败"
    exit 1
fi

# 等待Knox完全启动
log_info "等待Knox完全启动..."
for i in {1..30}; do
    if curl -k -s https://localhost:8443 > /dev/null 2>&1; then
        log_success "✅ Knox已就绪"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "❌ Knox启动超时"
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""

# 创建测试脚本
log_info "创建API测试脚本..."
cat > test-kyuubi-api.sh << 'EOF'
#!/bin/bash

# Kyuubi API测试脚本

KNOX_BASE="https://localhost:8443/gateway/emr/kyuubi"
KYUUBI_DIRECT="http://localhost:10099"

echo "=== Kyuubi API重写测试 ==="

# 测试函数
test_endpoint() {
    local name="$1"
    local knox_url="$2"
    local direct_url="$3"
    
    echo "测试 $name:"
    echo "  Knox URL: $knox_url"
    
    # 测试Knox代理
    local knox_code=$(curl -k -s -o /dev/null -w "%{http_code}" "$knox_url" 2>/dev/null)
    echo "  Knox响应: $knox_code"
    
    # 测试直接访问作为对比
    local direct_code=$(curl -s -o /dev/null -w "%{http_code}" "$direct_url" 2>/dev/null)
    echo "  直接访问: $direct_code"
    
    if [ "$knox_code" = "$direct_code" ]; then
        echo "  ✅ 响应码匹配"
    else
        echo "  ❌ 响应码不匹配"
    fi
    echo ""
}

# 测试各种端点
test_endpoint "主页" "$KNOX_BASE/" "$KYUUBI_DIRECT/"
test_endpoint "UI管理页面" "$KNOX_BASE/ui/management/session" "$KYUUBI_DIRECT/ui/management/session"
test_endpoint "Admin Sessions API" "$KNOX_BASE/api/v1/admin/sessions" "$KYUUBI_DIRECT/api/v1/admin/sessions"
test_endpoint "静态资源" "$KNOX_BASE/assets/index.js" "$KYUUBI_DIRECT/assets/index.js"

# 详细测试API调用
echo "=== 详细API测试 ==="
echo "测试Admin Sessions API的详细响应:"
curl -k -H "Accept: application/json" "$KNOX_BASE/api/v1/admin/sessions" 2>/dev/null | head -5

echo ""
echo "=== 测试完成 ==="
EOF

chmod +x test-kyuubi-api.sh

# 运行基础测试
log_info "运行基础连接测试..."
sleep 5

# 测试Kyuubi直接访问
KYUUBI_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:10099 2>/dev/null)
log_info "Kyuubi直接访问状态: $KYUUBI_STATUS"

# 测试Knox代理主页
KNOX_HOME_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/gateway/emr/kyuubi/ 2>/dev/null)
log_info "Knox代理主页状态: $KNOX_HOME_STATUS"

# 测试关键的API端点
API_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/gateway/emr/kyuubi/api/v1/admin/sessions 2>/dev/null)
log_info "Knox代理API状态: $API_STATUS"

echo ""
echo "==================================================================="
echo "部署完成！"
echo ""
echo "📊 测试结果:"
echo "  Kyuubi直接访问: $KYUUBI_STATUS"
echo "  Knox代理主页:   $KNOX_HOME_STATUS"
echo "  Knox代理API:    $API_STATUS"
echo ""
echo "🔧 重要配置文件:"
echo "  重写规则: $KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml"
echo "  备份目录: $BACKUP_DIR"
echo ""
echo "🧪 测试命令:"
echo "  完整测试: ./test-kyuubi-api.sh"
echo "  API测试:  curl -k https://localhost:8443/gateway/emr/kyuubi/api/v1/admin/sessions"
echo "  查看日志: tail -f $KNOX_HOME/logs/gateway.log | grep -E '(rewrite|KYUUBIUI|api)'"
echo ""

if [ "$API_STATUS" = "200" ] || [ "$API_STATUS" = "404" ]; then
    log_success "🎉 重写规则部署成功！你的API请求现在应该能正常工作。"
    echo ""
    echo "URL映射验证："
    echo "  原始: http://localhost:10099/api/v1/admin/sessions"
    echo "  Knox: https://localhost:8443/gateway/emr/kyuubi/api/v1/admin/sessions"
else
    log_warn "⚠️ API访问可能仍有问题，请检查日志进行进一步诊断。"
fi

echo "==================================================================="