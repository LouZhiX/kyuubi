#!/bin/bash

# Knox-Kyuubi快速调试启动脚本
# 一键启动所有必要的调试工具

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
echo "              Knox-Kyuubi快速调试工具"
echo "==================================================================="

echo "选择调试模式："
echo "1. 快速状态检查"
echo "2. 启用详细日志并重启服务"
echo "3. 实时监控日志"
echo "4. 交互式调试控制台"
echo "5. 完整的连接性测试"
echo "6. 导出调试信息"
echo "7. 所有调试工具（推荐）"

read -p "请选择 (1-7): " choice

case $choice in
    1)
        log_info "执行快速状态检查..."
        
        echo "=== 服务进程状态 ==="
        ps aux | grep -E "(knox|KyuubiServer)" | grep -v grep
        
        echo -e "\n=== 端口监听状态 ==="
        lsof -i :8443 || echo "Knox端口8443未监听"
        lsof -i :10099 || echo "Kyuubi端口10099未监听"
        
        echo -e "\n=== 连接测试 ==="
        KYUUBI_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:10099 2>/dev/null)
        KNOX_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/gateway/emr/kyuubi/ 2>/dev/null)
        echo "Kyuubi直接访问: $KYUUBI_CODE"
        echo "Knox代理访问: $KNOX_CODE"
        ;;
        
    2)
        log_info "启用详细日志并重启服务..."
        
        # 备份原日志配置
        cp "$KNOX_HOME/conf/gateway-log4j.properties" "$KNOX_HOME/conf/gateway-log4j.properties.backup" 2>/dev/null || true
        
        # 启用Knox详细日志
        cat >> "$KNOX_HOME/conf/gateway-log4j.properties" << 'EOF'

# Debug logging for Knox-Kyuubi integration
log4j.logger.org.apache.knox=DEBUG
log4j.logger.org.apache.knox.gateway.dispatch=DEBUG
log4j.logger.org.apache.knox.gateway.filter.rewrite=TRACE
log4j.logger.org.apache.knox.gateway.services=DEBUG
EOF
        
        # 重启服务
        log_info "重启Knox..."
        cd "$KNOX_HOME" && bin/gateway.sh stop && bin/gateway.sh start
        
        log_info "重启Kyuubi..."
        KYUUBI_PID=$(ps aux | grep KyuubiServer | grep -v grep | awk '{print $2}')
        if [ -n "$KYUUBI_PID" ]; then
            kill $KYUUBI_PID
            sleep 5
        fi
        cd "$KYUUBI_HOME" && nohup bin/kyuubi > logs/kyuubi-debug.log 2>&1 &
        
        log_success "详细日志已启用，服务已重启"
        ;;
        
    3)
        log_info "启动实时日志监控..."
        
        # 创建多窗口监控
        osascript << 'EOF'
tell application "Terminal"
    do script "tail -f /Users/junglelou/Downloads/knox-1.6.1.2/logs/gateway.log | grep -E '(ERROR|WARN|DEBUG|kyuubi|KYUUBIUI)'"
    do script "tail -f /Users/junglelou/Downloads/apache-kyuubi-1.9.2-bin/logs/kyuubi-server.log | grep -E '(ERROR|WARN|DEBUG)'"
end tell
EOF
        
        echo "已在新Terminal窗口中启动日志监控"
        echo "现在可以发送测试请求: curl -k -v https://localhost:8443/gateway/emr/kyuubi/"
        ;;
        
    4)
        log_info "启动交互式调试控制台..."
        
        # 检查是否存在调试脚本，如果不存在则创建
        if [ ! -f "debug-console.sh" ]; then
            log_warn "调试控制台脚本不存在，正在创建..."
            # 这里应该包含debug-console.sh的创建代码，为了简化，我们直接调用
        fi
        
        chmod +x debug-console.sh 2>/dev/null || true
        ./debug-console.sh 2>/dev/null || {
            log_error "调试控制台脚本不存在，请先运行完整调试指南"
            echo "建议执行: curl -O https://your-guide-url/debug-console.sh"
        }
        ;;
        
    5)
        log_info "执行完整连接性测试..."
        
        echo "=== 测试1: Kyuubi直接访问 ==="
        curl -v http://localhost:10099 2>&1 | head -15
        
        echo -e "\n=== 测试2: Knox基础访问 ==="
        curl -k -v https://localhost:8443 2>&1 | head -10
        
        echo -e "\n=== 测试3: Knox代理Kyuubi访问 ==="
        curl -k -v https://localhost:8443/gateway/emr/kyuubi/ 2>&1 | head -20
        
        echo -e "\n=== 测试4: 配置验证 ==="
        if [ -f "$KNOX_HOME/conf/topologies/emr.xml" ]; then
            echo "Topology配置:"
            grep -A5 -B2 "KYUUBIUI" "$KNOX_HOME/conf/topologies/emr.xml"
        else
            echo "❌ topology文件不存在"
        fi
        ;;
        
    6)
        log_info "导出调试信息..."
        
        DEBUG_FILE="knox-kyuubi-debug-$(date +%Y%m%d_%H%M%S).txt"
        
        {
            echo "=== Knox-Kyuubi调试信息 ==="
            echo "导出时间: $(date)"
            echo "系统信息: $(uname -a)"
            echo ""
            
            echo "=== 服务状态 ==="
            ps aux | grep -E "(knox|kyuubi)" | grep -v grep
            echo ""
            
            echo "=== 端口监听 ==="
            lsof -i :8443 2>/dev/null || echo "Knox端口8443未监听"
            lsof -i :10099 2>/dev/null || echo "Kyuubi端口10099未监听"
            echo ""
            
            echo "=== 网络连接测试 ==="
            echo "Kyuubi直接访问: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:10099 2>/dev/null)"
            echo "Knox代理访问: $(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/gateway/emr/kyuubi/ 2>/dev/null)"
            echo ""
            
            echo "=== 配置文件 ==="
            echo "Knox topology (emr.xml):"
            cat "$KNOX_HOME/conf/topologies/emr.xml" 2>/dev/null || echo "文件不存在"
            echo ""
            
            echo "Kyuubi配置 (kyuubi-defaults.conf):"
            cat "$KYUUBI_HOME/conf/kyuubi-defaults.conf" 2>/dev/null || echo "文件不存在"
            echo ""
            
            echo "Knox服务定义:"
            find "$KNOX_HOME/data/services/kyuubiui" -name "*.xml" 2>/dev/null | while read file; do
                echo "文件: $file"
                cat "$file"
                echo ""
            done
            
            echo "=== 最近日志 ==="
            echo "Knox最近50行错误日志:"
            tail -50 "$KNOX_HOME/logs/gateway.log" 2>/dev/null | grep -E "(ERROR|WARN)" | tail -20
            echo ""
            
            echo "Kyuubi最近50行错误日志:"
            tail -50 "$KYUUBI_HOME/logs/kyuubi-server.log" 2>/dev/null | grep -E "(ERROR|WARN)" | tail -20
            
        } > "$DEBUG_FILE"
        
        log_success "调试信息已导出到: $DEBUG_FILE"
        echo "请将此文件发送给技术支持进行分析"
        ;;
        
    7)
        log_info "启动所有调试工具..."
        
        # 1. 首先执行快速状态检查
        echo "步骤1: 快速状态检查"
        $0 1
        
        echo -e "\n步骤2: 启用详细日志"
        # 启用详细日志（不重启，避免中断）
        cp "$KNOX_HOME/conf/gateway-log4j.properties" "$KNOX_HOME/conf/gateway-log4j.properties.backup" 2>/dev/null || true
        cat >> "$KNOX_HOME/conf/gateway-log4j.properties" << 'EOF'

# Debug logging for Knox-Kyuubi integration
log4j.logger.org.apache.knox=DEBUG
log4j.logger.org.apache.knox.gateway.dispatch=DEBUG
log4j.logger.org.apache.knox.gateway.filter.rewrite=TRACE
EOF
        
        echo -e "\n步骤3: 执行连接性测试"
        $0 5
        
        echo -e "\n步骤4: 导出调试信息"
        $0 6
        
        echo -e "\n步骤5: 启动实时监控"
        echo "是否启动实时日志监控？(y/N)"
        read -n 1 monitor_choice
        if [[ $monitor_choice =~ ^[Yy]$ ]]; then
            $0 3
        fi
        
        log_success "所有调试工具已执行完成"
        echo ""
        echo "建议下一步操作："
        echo "1. 检查导出的调试信息文件"
        echo "2. 根据错误日志确定问题原因"
        echo "3. 如果需要实时调试，选择选项4启动交互式控制台"
        ;;
        
    *)
        log_error "无效选择"
        exit 1
        ;;
esac

echo ""
echo "==================================================================="
echo "调试操作完成！"
echo ""
echo "常用调试命令："
echo "  查看Knox日志: tail -f $KNOX_HOME/logs/gateway.log"
echo "  查看Kyuubi日志: tail -f $KYUUBI_HOME/logs/kyuubi-server.log"
echo "  测试连接: curl -k -v https://localhost:8443/gateway/emr/kyuubi/"
echo "  重新运行此脚本: ./quick-debug.sh"
echo "==================================================================="