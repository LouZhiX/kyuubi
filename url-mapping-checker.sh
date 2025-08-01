#!/bin/bash

# Knox URL映射错误诊断脚本
# 专门检查Knox到Kyuubi的URL映射是否正确

echo "==================================================================="
echo "              Knox-Kyuubi URL映射诊断工具"
echo "==================================================================="

# 设置路径变量
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

echo "步骤1: 检查当前topology配置中的URL映射..."
TOPOLOGY_FILE="$KNOX_HOME/conf/topologies/emr.xml"

if [ -f "$TOPOLOGY_FILE" ]; then
    log_info "检查topology文件: $TOPOLOGY_FILE"
    
    # 提取KYUUBIUI服务的URL配置
    KYUUBI_URL=$(grep -A10 "KYUUBIUI" "$TOPOLOGY_FILE" | grep "<url>" | sed 's/.*<url>\(.*\)<\/url>.*/\1/' | tr -d ' ')
    
    if [ -n "$KYUUBI_URL" ]; then
        log_info "发现KYUUBIUI服务URL配置: $KYUUBI_URL"
        
        # 检查URL是否正确
        if [[ "$KYUUBI_URL" == *"localhost:8443"* ]] || [[ "$KYUUBI_URL" == *"gateway/emr/kyuubi"* ]]; then
            log_error "❌ URL映射错误：服务URL指向Knox自己！"
            log_error "   当前配置: $KYUUBI_URL"
            log_error "   正确配置应该是: http://localhost:10099"
            MAPPING_ERROR=true
        elif [[ "$KYUUBI_URL" == "http://localhost:10099"* ]]; then
            log_success "✅ 服务URL配置正确"
            MAPPING_ERROR=false
        else
            log_warn "⚠️  服务URL配置可能有问题: $KYUUBI_URL"
            log_warn "   建议使用: http://localhost:10099"
            MAPPING_ERROR=true
        fi
    else
        log_error "❌ 未找到KYUUBIUI服务URL配置"
        MAPPING_ERROR=true
    fi
else
    log_error "❌ topology文件不存在: $TOPOLOGY_FILE"
    MAPPING_ERROR=true
fi

echo ""
echo "步骤2: 检查Knox日志中的URL重写痕迹..."

GATEWAY_LOG="$KNOX_HOME/logs/gateway.log"
if [ -f "$GATEWAY_LOG" ]; then
    log_info "分析gateway日志中的URL模式..."
    
    # 检查是否有循环调用的证据
    LOOP_CALLS=$(grep -c "localhost:8443/gateway/emr/kyuubi" "$GATEWAY_LOG" 2>/dev/null || echo "0")
    if [ "$LOOP_CALLS" -gt 0 ]; then
        log_error "❌ 发现循环调用证据！Knox试图调用自己 ($LOOP_CALLS 次)"
        log_error "   错误模式: localhost:8443/gateway/emr/kyuubi"
        
        # 显示最近的错误
        echo "   最近的错误日志:"
        grep "localhost:8443/gateway/emr/kyuubi" "$GATEWAY_LOG" | tail -3 | while read line; do
            echo "   $(echo $line | cut -c1-100)..."
        done
        MAPPING_ERROR=true
    else
        log_success "✅ 未发现循环调用"
    fi
    
    # 检查是否有正确的Kyuubi URL调用
    CORRECT_CALLS=$(grep -c "localhost:10099" "$GATEWAY_LOG" 2>/dev/null || echo "0")
    if [ "$CORRECT_CALLS" -gt 0 ]; then
        log_success "✅ 发现正确的Kyuubi调用 ($CORRECT_CALLS 次)"
    else
        log_warn "⚠️  未发现对Kyuubi的正确调用"
    fi
    
    # 检查SSL错误
    SSL_ERRORS=$(grep -c "SSLHandshakeException" "$GATEWAY_LOG" 2>/dev/null || echo "0")
    if [ "$SSL_ERRORS" -gt 0 ]; then
        log_error "❌ 发现SSL握手错误 ($SSL_ERRORS 次) - 通常表示URL映射错误"
        MAPPING_ERROR=true
    fi
else
    log_warn "⚠️  gateway日志文件不存在，无法分析URL重写"
fi

echo ""
echo "步骤3: 检查服务定义和重写规则..."

SERVICE_DIR="$KNOX_HOME/data/services/kyuubiui"
if [ -d "$SERVICE_DIR" ]; then
    log_success "✅ 找到KYUUBIUI服务定义目录"
    
    # 检查service.xml
    if [ -f "$SERVICE_DIR/1.9.0/service.xml" ]; then
        log_success "✅ service.xml存在"
        
        # 检查路由配置
        ROUTES=$(grep -A5 "<routes>" "$SERVICE_DIR/1.9.0/service.xml")
        if [[ "$ROUTES" == *"/kyuubi"* ]]; then
            log_success "✅ 路由配置包含/kyuubi路径"
        else
            log_error "❌ 路由配置可能有问题"
            MAPPING_ERROR=true
        fi
    else
        log_error "❌ service.xml文件缺失"
        MAPPING_ERROR=true
    fi
    
    # 检查rewrite.xml
    if [ -f "$SERVICE_DIR/1.9.0/rewrite.xml" ]; then
        log_success "✅ rewrite.xml存在"
        
        # 检查重写规则
        INBOUND_RULES=$(grep -c "dir=\"IN\"" "$SERVICE_DIR/1.9.0/rewrite.xml" 2>/dev/null || echo "0")
        if [ "$INBOUND_RULES" -gt 0 ]; then
            log_success "✅ 找到入站重写规则 ($INBOUND_RULES 个)"
        else
            log_error "❌ 缺少入站重写规则"
            MAPPING_ERROR=true
        fi
        
        # 检查模板是否正确
        TEMPLATE_CHECK=$(grep "serviceUrl\[KYUUBIUI\]" "$SERVICE_DIR/1.9.0/rewrite.xml" 2>/dev/null)
        if [ -n "$TEMPLATE_CHECK" ]; then
            log_success "✅ 重写模板配置正确"
        else
            log_error "❌ 重写模板配置错误或缺失"
            MAPPING_ERROR=true
        fi
    else
        log_error "❌ rewrite.xml文件缺失"
        MAPPING_ERROR=true
    fi
else
    log_error "❌ KYUUBIUI服务定义目录不存在"
    MAPPING_ERROR=true
fi

echo ""
echo "步骤4: 实际URL重写测试..."

log_info "测试Knox URL重写过程..."

# 模拟Knox的URL重写过程
if [ "$MAPPING_ERROR" = false ]; then
    log_info "发送测试请求到Knox..."
    
    # 发送请求并捕获响应头
    RESPONSE=$(curl -k -s -I https://localhost:8443/gateway/emr/kyuubi/ 2>&1)
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP" | awk '{print $2}')
    
    log_info "Knox响应码: $HTTP_CODE"
    
    # 检查是否有Location头（重定向）
    LOCATION=$(echo "$RESPONSE" | grep -i "Location:" | cut -d' ' -f2- | tr -d '\r\n')
    if [ -n "$LOCATION" ]; then
        log_info "重定向到: $LOCATION"
        
        if [[ "$LOCATION" == *"localhost:8443"* ]]; then
            log_error "❌ 重定向到Knox自己 - 确认URL映射错误！"
        else
            log_success "✅ 重定向目标正确"
        fi
    fi
fi

echo ""
echo "步骤5: 生成URL映射诊断报告..."

echo "==================================================================="
echo "                    URL映射诊断报告"
echo "==================================================================="

if [ "$MAPPING_ERROR" = true ]; then
    log_error "❌ 检测到URL映射错误！"
    echo ""
    echo "发现的问题："
    
    if [[ "$KYUUBI_URL" == *"localhost:8443"* ]]; then
        echo "  1. topology配置错误：服务URL指向Knox自己"
        echo "     当前: $KYUUBI_URL"
        echo "     应该: http://localhost:10099"
    fi
    
    if [ "$LOOP_CALLS" -gt 0 ]; then
        echo "  2. 检测到循环调用：Knox试图连接自己"
    fi
    
    if [ "$SSL_ERRORS" -gt 0 ]; then
        echo "  3. SSL握手错误：通常由错误的URL映射引起"
    fi
    
    if [ ! -d "$SERVICE_DIR" ]; then
        echo "  4. 服务定义缺失：Knox不知道如何处理KYUUBIUI请求"
    fi
    
    echo ""
    echo "修复建议："
    echo "  1. 修正topology配置中的服务URL"
    echo "  2. 确保服务定义文件存在且正确"
    echo "  3. 检查重写规则是否完整"
    echo "  4. 重启Knox服务"
    
else
    log_success "✅ URL映射配置看起来正确！"
    echo ""
    echo "验证的配置："
    echo "  ✅ 服务URL正确指向Kyuubi"
    echo "  ✅ 服务定义存在"
    echo "  ✅ 重写规则配置正确"
    echo "  ✅ 无循环调用检测"
fi

echo ""
echo "==================================================================="

# 如果发现错误，提供快速修复命令
if [ "$MAPPING_ERROR" = true ]; then
    echo ""
    echo "快速修复命令："
    echo ""
    echo "# 1. 修复topology配置"
    echo "sed -i '' 's|<url>.*</url>|<url>http://localhost:10099</url>|' $TOPOLOGY_FILE"
    echo ""
    echo "# 2. 重启Knox"
    echo "cd $KNOX_HOME && bin/gateway.sh restart"
    echo ""
    echo "# 3. 测试修复结果"
    echo "curl -k -v https://localhost:8443/gateway/emr/kyuubi/"
fi