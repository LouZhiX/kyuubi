#!/bin/bash

#
# Knox-Kyuubi连接问题诊断脚本
# 用于排查和解决Knox访问Kyuubi WebUI时出现的500错误
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 配置参数
KNOX_HOME=${KNOX_HOME:-"/opt/knox"}
KYUUBI_HOME=${KYUUBI_HOME:-"/opt/kyuubi"}
KNOX_GATEWAY_HOST=${KNOX_GATEWAY_HOST:-"localhost"}
KNOX_GATEWAY_PORT=${KNOX_GATEWAY_PORT:-8443}
KYUUBI_WEB_HOST=${KYUUBI_WEB_HOST:-"localhost"}
KYUUBI_WEB_PORT=${KYUUBI_WEB_PORT:-10099}
TOPOLOGY_NAME=${TOPOLOGY_NAME:-"emr"}

echo "======================================================================="
echo "                    Knox-Kyuubi连接问题诊断工具                        "
echo "======================================================================="

# 1. 检查Knox和Kyuubi服务状态
check_service_status() {
    log_info "检查服务状态..."
    
    # 检查Knox进程
    if pgrep -f "knox" > /dev/null; then
        log_success "Knox服务正在运行"
    else
        log_error "Knox服务未运行"
        return 1
    fi
    
    # 检查Kyuubi进程
    if pgrep -f "kyuubi" > /dev/null; then
        log_success "Kyuubi服务正在运行"
    else
        log_error "Kyuubi服务未运行"
        return 1
    fi
}

# 2. 检查端口连通性
check_connectivity() {
    log_info "检查网络连通性..."
    
    # 检查Knox端口
    if nc -z ${KNOX_GATEWAY_HOST} ${KNOX_GATEWAY_PORT} 2>/dev/null; then
        log_success "Knox端口 ${KNOX_GATEWAY_PORT} 可访问"
    else
        log_error "Knox端口 ${KNOX_GATEWAY_PORT} 不可访问"
    fi
    
    # 检查Kyuubi WebUI端口
    if nc -z ${KYUUBI_WEB_HOST} ${KYUUBI_WEB_PORT} 2>/dev/null; then
        log_success "Kyuubi WebUI端口 ${KYUUBI_WEB_PORT} 可访问"
    else
        log_error "Kyuubi WebUI端口 ${KYUUBI_WEB_PORT} 不可访问"
        log_warn "请检查Kyuubi配置文件中的kyuubi.frontend.bind.host和kyuubi.frontend.bind.port设置"
    fi
}

# 3. 检查Knox topology配置
check_knox_topology() {
    log_info "检查Knox topology配置..."
    
    TOPOLOGY_FILE="${KNOX_HOME}/conf/topologies/${TOPOLOGY_NAME}.xml"
    
    if [[ -f "${TOPOLOGY_FILE}" ]]; then
        log_success "找到topology文件: ${TOPOLOGY_FILE}"
        
        # 检查Kyuubi服务配置
        if grep -q "KYUUBIUI" "${TOPOLOGY_FILE}"; then
            log_success "topology中包含KYUUBIUI服务配置"
        else
            log_error "topology中缺少KYUUBIUI服务配置"
            log_warn "请确保topology文件中包含以下配置:"
            cat << 'EOF'
<service>
    <role>KYUUBIUI</role>
    <url>http://your-kyuubi-host:10099</url>
</service>
EOF
        fi
        
        # 检查URL配置
        KYUUBI_URL=$(grep -A2 "KYUUBIUI" "${TOPOLOGY_FILE}" | grep "<url>" | sed 's/.*<url>\(.*\)<\/url>.*/\1/')
        if [[ -n "${KYUUBI_URL}" ]]; then
            log_info "配置的Kyuubi URL: ${KYUUBI_URL}"
        fi
    else
        log_error "找不到topology文件: ${TOPOLOGY_FILE}"
    fi
}

# 4. 检查Knox服务定义
check_knox_service_definition() {
    log_info "检查Knox服务定义..."
    
    SERVICE_DIR="${KNOX_HOME}/data/services/kyuubiui"
    
    if [[ -d "${SERVICE_DIR}" ]]; then
        log_success "找到Kyuubi服务定义目录: ${SERVICE_DIR}"
        
        # 检查service.xml
        if [[ -f "${SERVICE_DIR}/1.9.0/service.xml" ]]; then
            log_success "找到service.xml文件"
        else
            log_error "找不到service.xml文件"
        fi
        
        # 检查rewrite.xml
        if [[ -f "${SERVICE_DIR}/1.9.0/rewrite.xml" ]]; then
            log_success "找到rewrite.xml文件"
        else
            log_error "找不到rewrite.xml文件"
        fi
    else
        log_error "找不到Kyuubi服务定义目录: ${SERVICE_DIR}"
    fi
}

# 5. 测试HTTP连接
test_http_connectivity() {
    log_info "测试HTTP连接..."
    
    # 直接测试Kyuubi WebUI
    KYUUBI_URL="http://${KYUUBI_WEB_HOST}:${KYUUBI_WEB_PORT}"
    
    if curl -s --connect-timeout 5 "${KYUUBI_URL}" > /dev/null; then
        log_success "Kyuubi WebUI直接访问正常: ${KYUUBI_URL}"
    else
        log_error "Kyuubi WebUI直接访问失败: ${KYUUBI_URL}"
        log_warn "请检查Kyuubi配置并确保WebUI已启用"
    fi
    
    # 测试通过Knox访问
    KNOX_URL="https://${KNOX_GATEWAY_HOST}:${KNOX_GATEWAY_PORT}/gateway/${TOPOLOGY_NAME}/kyuubi"
    
    log_info "尝试通过Knox访问: ${KNOX_URL}"
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "${KNOX_URL}")
    
    if [[ "${HTTP_CODE}" == "200" ]]; then
        log_success "Knox代理访问成功"
    else
        log_error "Knox代理访问失败，HTTP状态码: ${HTTP_CODE}"
    fi
}

# 6. 检查日志文件
check_logs() {
    log_info "检查相关日志文件..."
    
    # Knox gateway日志
    KNOX_GATEWAY_LOG="${KNOX_HOME}/logs/gateway.log"
    if [[ -f "${KNOX_GATEWAY_LOG}" ]]; then
        log_info "最近的Knox gateway错误:"
        tail -20 "${KNOX_GATEWAY_LOG}" | grep -i "error\|exception" | tail -5
    fi
    
    # Knox ldap日志
    KNOX_LDAP_LOG="${KNOX_HOME}/logs/ldap.log"
    if [[ -f "${KNOX_LDAP_LOG}" ]]; then
        log_info "最近的Knox LDAP错误:"
        tail -20 "${KNOX_LDAP_LOG}" | grep -i "error\|exception" | tail -5
    fi
    
    # Kyuubi日志
    KYUUBI_LOG="${KYUUBI_HOME}/logs/kyuubi-server.log"
    if [[ -f "${KYUUBI_LOG}" ]]; then
        log_info "最近的Kyuubi错误:"
        tail -20 "${KYUUBI_LOG}" | grep -i "error\|exception" | tail -5
    fi
}

# 7. 生成修复建议
generate_fix_suggestions() {
    log_info "生成修复建议..."
    
    echo ""
    echo "======================================================================="
    echo "                           修复建议                                    "
    echo "======================================================================="
    
    echo "1. 检查Kyuubi配置文件 (${KYUUBI_HOME}/conf/kyuubi-defaults.conf):"
    echo "   kyuubi.frontend.bind.host=0.0.0.0"
    echo "   kyuubi.frontend.bind.port=10099"
    echo "   kyuubi.frontend.protocols=HTTP"
    echo ""
    
    echo "2. 检查防火墙设置:"
    echo "   sudo firewall-cmd --add-port=${KYUUBI_WEB_PORT}/tcp --permanent"
    echo "   sudo firewall-cmd --reload"
    echo ""
    
    echo "3. 重启服务:"
    echo "   ${KYUUBI_HOME}/bin/kyuubi stop"
    echo "   ${KYUUBI_HOME}/bin/kyuubi start"
    echo "   ${KNOX_HOME}/bin/gateway.sh stop"
    echo "   ${KNOX_HOME}/bin/gateway.sh start"
    echo ""
    
    echo "4. 检查Knox topology配置中的URL是否正确"
    echo "5. 确保Knox服务定义文件已正确部署"
    echo "6. 检查网络连通性和DNS解析"
}

# 主函数
main() {
    check_service_status
    echo ""
    
    check_connectivity
    echo ""
    
    check_knox_topology
    echo ""
    
    check_knox_service_definition
    echo ""
    
    test_http_connectivity
    echo ""
    
    check_logs
    echo ""
    
    generate_fix_suggestions
}

# 执行主函数
main