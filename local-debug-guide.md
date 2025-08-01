# Knox-Kyuubi本地调试完整指南

## 🎯 调试策略概览

本地调试Knox-Kyuubi集成需要多层次的方法：
1. **日志级别调试** - 启用详细日志
2. **网络层调试** - 分析HTTP请求/响应
3. **配置验证调试** - 验证配置正确性
4. **进程级调试** - 监控服务状态
5. **实时调试** - 动态跟踪请求流程

## 🔧 1. 启用详细日志调试

### Knox日志调试配置

#### 方法1: 修改log4j配置
```bash
# 编辑Knox的log4j配置
vim $KNOX_HOME/conf/gateway-log4j.properties

# 添加以下调试配置
log4j.logger.org.apache.knox=DEBUG
log4j.logger.org.apache.knox.gateway.dispatch=DEBUG
log4j.logger.org.apache.knox.gateway.filter.rewrite=DEBUG
log4j.logger.org.apache.knox.gateway.services=DEBUG
```

#### 方法2: 运行时启用调试
```bash
# 设置Knox调试环境变量
export KNOX_GATEWAY_LOG_OPTS="-Dknox.gateway.log.level=DEBUG"

# 重启Knox
cd $KNOX_HOME
bin/gateway.sh stop
bin/gateway.sh start
```

### Kyuubi日志调试配置

```bash
# 编辑Kyuubi log4j配置
vim $KYUUBI_HOME/conf/log4j2.xml

# 或者创建调试配置文件
cat > $KYUUBI_HOME/conf/log4j2-debug.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Configuration status="INFO">
    <Appenders>
        <Console name="stdout" target="SYSTEM_OUT">
            <PatternLayout pattern="%d{HH:mm:ss.SSS} [%t] %-5level %logger{36} - %msg%n"/>
        </Console>
        <File name="file" fileName="logs/kyuubi-debug.log">
            <PatternLayout pattern="%d{yyyy-MM-dd HH:mm:ss.SSS} [%t] %-5level %logger{36} - %msg%n"/>
        </File>
    </Appenders>
    <Loggers>
        <Logger name="org.apache.kyuubi" level="DEBUG" additivity="false">
            <AppenderRef ref="stdout"/>
            <AppenderRef ref="file"/>
        </Logger>
        <Logger name="org.apache.kyuubi.server.http" level="TRACE" additivity="false">
            <AppenderRef ref="stdout"/>
            <AppenderRef ref="file"/>
        </Logger>
        <Root level="INFO">
            <AppenderRef ref="stdout"/>
            <AppenderRef ref="file"/>
        </Root>
    </Loggers>
</Configuration>
EOF

# 启动Kyuubi时指定调试配置
$KYUUBI_HOME/bin/kyuubi --conf log4j2.configurationFile=$KYUUBI_HOME/conf/log4j2-debug.xml
```

## 🌐 2. 网络层调试

### HTTP请求跟踪

#### 使用curl进行详细调试
```bash
# 完整的HTTP跟踪
curl -k -v -H "User-Agent: Debug-Client" \
  --trace-ascii curl-trace.log \
  --trace-time \
  https://localhost:8443/gateway/emr/kyuubi/

# 分析跟踪结果
cat curl-trace.log
```

#### 使用netcat监听端口
```bash
# 监听Knox端口
nc -l 8444 &

# 配置端口转发（如果需要）
sudo pfctl -f - << 'EOF'
rdr pass on lo0 inet proto tcp from any to any port 8443 -> 127.0.0.1 port 8444
EOF
```

#### 使用tcpdump抓包分析
```bash
# 抓取本地回环接口的包
sudo tcpdump -i lo0 -A -s 0 port 8443 or port 10099

# 保存到文件分析
sudo tcpdump -i lo0 -w knox-kyuubi-debug.pcap port 8443 or port 10099
```

### Knox URL重写跟踪

#### 创建URL重写调试脚本
```bash
cat > debug-url-rewrite.sh << 'EOF'
#!/bin/bash

# Knox URL重写调试脚本
KNOX_HOME="/Users/junglelou/Downloads/knox-1.6.1.2"

echo "=== Knox URL重写调试 ==="

# 1. 检查重写规则
echo "1. 重写规则检查:"
if [ -f "$KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml" ]; then
    echo "✅ rewrite.xml存在"
    grep -E "(pattern|template)" "$KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml"
else
    echo "❌ rewrite.xml不存在"
fi

# 2. 实时监控重写日志
echo -e "\n2. 实时监控Knox重写日志:"
tail -f "$KNOX_HOME/logs/gateway.log" | grep -E "(rewrite|dispatch|KYUUBIUI)" &
TAIL_PID=$!

# 3. 发送测试请求
echo -e "\n3. 发送测试请求..."
sleep 2
curl -k -s https://localhost:8443/gateway/emr/kyuubi/ > /dev/null

# 4. 停止监控
sleep 5
kill $TAIL_PID 2>/dev/null

echo -e "\n=== 调试完成 ==="
EOF

chmod +x debug-url-rewrite.sh
./debug-url-rewrite.sh
```

## 📊 3. 配置验证调试

### 创建配置验证脚本

```bash
cat > debug-config-validation.sh << 'EOF'
#!/bin/bash

# Knox-Kyuubi配置验证调试脚本
KNOX_HOME="/Users/junglelou/Downloads/knox-1.6.1.2"
KYUUBI_HOME="/Users/junglelou/Downloads/apache-kyuubi-1.9.2-bin"

echo "=== 配置验证调试 ==="

# 1. Kyuubi配置验证
echo "1. Kyuubi配置验证:"
if [ -f "$KYUUBI_HOME/conf/kyuubi-defaults.conf" ]; then
    echo "✅ Kyuubi配置文件存在"
    echo "关键配置项:"
    grep -E "(frontend|bind|port|protocol)" "$KYUUBI_HOME/conf/kyuubi-defaults.conf" | head -10
else
    echo "❌ Kyuubi配置文件不存在"
fi

# 2. Knox topology验证
echo -e "\n2. Knox topology验证:"
TOPOLOGY_FILE="$KNOX_HOME/conf/topologies/emr.xml"
if [ -f "$TOPOLOGY_FILE" ]; then
    echo "✅ topology文件存在"
    echo "KYUUBIUI服务配置:"
    xmllint --format "$TOPOLOGY_FILE" | grep -A10 -B2 "KYUUBIUI" || \
    grep -A10 -B2 "KYUUBIUI" "$TOPOLOGY_FILE"
else
    echo "❌ topology文件不存在"
fi

# 3. Knox服务定义验证
echo -e "\n3. Knox服务定义验证:"
SERVICE_DIR="$KNOX_HOME/data/services/kyuubiui"
if [ -d "$SERVICE_DIR" ]; then
    echo "✅ 服务定义目录存在"
    find "$SERVICE_DIR" -name "*.xml" -exec echo "文件: {}" \; -exec head -5 {} \;
else
    echo "❌ 服务定义目录不存在"
fi

# 4. 端口监听验证
echo -e "\n4. 端口监听验证:"
echo "Kyuubi端口10099:"
lsof -i :10099 || echo "端口10099未监听"
echo "Knox端口8443:"
lsof -i :8443 || echo "端口8443未监听"

# 5. 进程状态验证
echo -e "\n5. 进程状态验证:"
echo "Kyuubi进程:"
ps aux | grep KyuubiServer | grep -v grep || echo "Kyuubi进程未运行"
echo "Knox进程:"
ps aux | grep knox | grep -v grep || echo "Knox进程未运行"

echo -e "\n=== 验证完成 ==="
EOF

chmod +x debug-config-validation.sh
./debug-config-validation.sh
```

## 🔍 4. 实时调试监控

### 创建实时监控脚本

```bash
cat > debug-realtime-monitor.sh << 'EOF'
#!/bin/bash

# Knox-Kyuubi实时调试监控脚本
KNOX_HOME="/Users/junglelou/Downloads/knox-1.6.1.2"
KYUUBI_HOME="/Users/junglelou/Downloads/apache-kyuubi-1.9.2-bin"

echo "=== Knox-Kyuubi实时调试监控 ==="
echo "按Ctrl+C停止监控"

# 创建多个监控窗口
trap 'kill $(jobs -p) 2>/dev/null' EXIT

# 1. Knox日志监控
echo "启动Knox日志监控..."
if [ -f "$KNOX_HOME/logs/gateway.log" ]; then
    tail -f "$KNOX_HOME/logs/gateway.log" | \
    while read line; do
        echo "[KNOX] $(date '+%H:%M:%S') $line"
    done | grep -E "(ERROR|WARN|kyuubi|KYUUBIUI|dispatch)" &
fi

# 2. Kyuubi日志监控
echo "启动Kyuubi日志监控..."
if [ -f "$KYUUBI_HOME/logs/kyuubi-server.log" ]; then
    tail -f "$KYUUBI_HOME/logs/kyuubi-server.log" | \
    while read line; do
        echo "[KYUUBI] $(date '+%H:%M:%S') $line"
    done | grep -E "(ERROR|WARN|frontend|http)" &
fi

# 3. 网络连接监控
echo "启动网络连接监控..."
while true; do
    echo "[NET] $(date '+%H:%M:%S') Connections:"
    netstat -an | grep -E "(8443|10099)" | head -5
    sleep 10
done &

# 4. 进程监控
echo "启动进程监控..."
while true; do
    KNOX_PID=$(ps aux | grep knox | grep -v grep | awk '{print $2}' | head -1)
    KYUUBI_PID=$(ps aux | grep KyuubiServer | grep -v grep | awk '{print $2}' | head -1)
    echo "[PROC] $(date '+%H:%M:%S') Knox PID: ${KNOX_PID:-N/A}, Kyuubi PID: ${KYUUBI_PID:-N/A}"
    sleep 15
done &

# 等待用户中断
echo -e "\n监控已启动，现在可以在另一个终端发送测试请求："
echo "curl -k -v https://localhost:8443/gateway/emr/kyuubi/"
echo -e "\n按任意键停止监控..."
read -n 1
EOF

chmod +x debug-realtime-monitor.sh
```

## 🐛 5. 分层调试方法

### Level 1: 基础连通性调试
```bash
# 测试Kyuubi基础连通性
curl -v http://localhost:10099
telnet localhost 10099

# 测试Knox基础连通性
curl -k -v https://localhost:8443
telnet localhost 8443
```

### Level 2: 服务发现调试
```bash
# 检查Knox是否识别KYUUBIUI服务
grep -r "KYUUBIUI" $KNOX_HOME/data/services/
grep -r "KYUUBIUI" $KNOX_HOME/logs/

# 检查topology部署状态
ls -la $KNOX_HOME/data/deployments/
```

### Level 3: URL重写调试
```bash
# 启用URL重写详细日志
echo "log4j.logger.org.apache.knox.gateway.filter.rewrite=TRACE" >> \
  $KNOX_HOME/conf/gateway-log4j.properties

# 重启Knox并观察重写过程
$KNOX_HOME/bin/gateway.sh restart
tail -f $KNOX_HOME/logs/gateway.log | grep -i rewrite
```

### Level 4: HTTP请求流调试
```bash
# 创建HTTP流跟踪脚本
cat > debug-http-flow.sh << 'EOF'
#!/bin/bash

echo "=== HTTP请求流调试 ==="

# 1. 发送请求并捕获所有头信息
echo "1. 发送请求到Knox..."
curl -k -I -v https://localhost:8443/gateway/emr/kyuubi/ 2>&1 | tee http-flow.log

# 2. 分析响应头
echo -e "\n2. 分析响应头..."
grep -E "(HTTP|Location|Content-Type|Server)" http-flow.log

# 3. 检查是否有重定向
echo -e "\n3. 检查重定向..."
LOCATION=$(grep -i "Location:" http-flow.log | cut -d' ' -f2-)
if [ -n "$LOCATION" ]; then
    echo "发现重定向到: $LOCATION"
    if [[ "$LOCATION" == *"8443"* ]]; then
        echo "❌ 错误：重定向到Knox自己"
    else
        echo "✅ 重定向目标看起来正确"
    fi
else
    echo "无重定向"
fi

# 4. 测试最终目标
echo -e "\n4. 直接测试Kyuubi..."
curl -I http://localhost:10099 2>&1 | head -5

echo -e "\n=== 调试完成 ==="
EOF

chmod +x debug-http-flow.sh
./debug-http-flow.sh
```

## 🎛️ 6. 交互式调试环境

### 创建调试控制台
```bash
cat > debug-console.sh << 'EOF'
#!/bin/bash

# Knox-Kyuubi交互式调试控制台
KNOX_HOME="/Users/junglelou/Downloads/knox-1.6.1.2"
KYUUBI_HOME="/Users/junglelou/Downloads/apache-kyuubi-1.9.2-bin"

show_menu() {
    echo "==============================================="
    echo "     Knox-Kyuubi调试控制台"
    echo "==============================================="
    echo "1. 查看服务状态"
    echo "2. 测试连接性"
    echo "3. 查看实时日志"
    echo "4. 验证配置"
    echo "5. 发送测试请求"
    echo "6. 重启服务"
    echo "7. 清理日志"
    echo "8. 导出调试信息"
    echo "9. 退出"
    echo "==============================================="
}

check_status() {
    echo "=== 服务状态检查 ==="
    echo "Knox进程: $(ps aux | grep knox | grep -v grep | wc -l) 个"
    echo "Kyuubi进程: $(ps aux | grep KyuubiServer | grep -v grep | wc -l) 个"
    echo "Knox端口8443: $(lsof -i :8443 | wc -l) 个连接"
    echo "Kyuubi端口10099: $(lsof -i :10099 | wc -l) 个连接"
}

test_connectivity() {
    echo "=== 连接性测试 ==="
    echo "测试Kyuubi直接访问..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:10099)
    echo "Kyuubi HTTP状态: $HTTP_CODE"
    
    echo "测试Knox代理访问..."
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/gateway/emr/kyuubi/)
    echo "Knox代理HTTP状态: $HTTP_CODE"
}

view_logs() {
    echo "=== 实时日志查看 ==="
    echo "1. Knox日志"
    echo "2. Kyuubi日志"
    echo "3. 同时查看"
    read -p "选择 (1-3): " log_choice
    
    case $log_choice in
        1) tail -f "$KNOX_HOME/logs/gateway.log" | grep -E "(ERROR|WARN|kyuubi)" ;;
        2) tail -f "$KYUUBI_HOME/logs/kyuubi-server.log" | grep -E "(ERROR|WARN)" ;;
        3) 
            tail -f "$KNOX_HOME/logs/gateway.log" | sed 's/^/[KNOX] /' &
            tail -f "$KYUUBI_HOME/logs/kyuubi-server.log" | sed 's/^/[KYUUBI] /' &
            wait
            ;;
    esac
}

send_test_request() {
    echo "=== 发送测试请求 ==="
    echo "发送请求到Knox代理..."
    curl -k -v https://localhost:8443/gateway/emr/kyuubi/ 2>&1 | head -20
}

export_debug_info() {
    DEBUG_FILE="knox-kyuubi-debug-$(date +%Y%m%d_%H%M%S).txt"
    echo "=== 导出调试信息到 $DEBUG_FILE ==="
    
    {
        echo "=== Knox-Kyuubi调试信息 ==="
        echo "导出时间: $(date)"
        echo ""
        
        echo "=== 服务状态 ==="
        ps aux | grep -E "(knox|kyuubi)" | grep -v grep
        echo ""
        
        echo "=== 端口监听 ==="
        lsof -i :8443
        lsof -i :10099
        echo ""
        
        echo "=== 配置文件 ==="
        echo "Knox topology:"
        cat "$KNOX_HOME/conf/topologies/emr.xml" 2>/dev/null || echo "文件不存在"
        echo ""
        echo "Kyuubi配置:"
        cat "$KYUUBI_HOME/conf/kyuubi-defaults.conf" 2>/dev/null || echo "文件不存在"
        echo ""
        
        echo "=== 最近日志 ==="
        echo "Knox最近20行日志:"
        tail -20 "$KNOX_HOME/logs/gateway.log" 2>/dev/null || echo "日志文件不存在"
        echo ""
        echo "Kyuubi最近20行日志:"
        tail -20 "$KYUUBI_HOME/logs/kyuubi-server.log" 2>/dev/null || echo "日志文件不存在"
        
    } > "$DEBUG_FILE"
    
    echo "调试信息已导出到: $DEBUG_FILE"
}

# 主循环
while true; do
    show_menu
    read -p "请选择 (1-9): " choice
    
    case $choice in
        1) check_status ;;
        2) test_connectivity ;;
        3) view_logs ;;
        4) ./debug-config-validation.sh ;;
        5) send_test_request ;;
        6) 
            echo "重启服务..."
            cd "$KNOX_HOME" && bin/gateway.sh restart
            cd "$KYUUBI_HOME" && bin/kyuubi stop && bin/kyuubi start
            ;;
        7) 
            echo "清理日志..."
            > "$KNOX_HOME/logs/gateway.log"
            > "$KYUUBI_HOME/logs/kyuubi-server.log"
            echo "日志已清理"
            ;;
        8) export_debug_info ;;
        9) echo "退出调试控制台"; exit 0 ;;
        *) echo "无效选择，请重新输入" ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
done
EOF

chmod +x debug-console.sh
```

## 🚀 7. 快速调试命令集合

### 一键启动所有调试
```bash
# 创建一键调试启动脚本
cat > start-debug.sh << 'EOF'
#!/bin/bash

echo "启动Knox-Kyuubi完整调试环境..."

# 1. 启用详细日志
echo "log4j.logger.org.apache.knox=DEBUG" >> $KNOX_HOME/conf/gateway-log4j.properties

# 2. 重启服务
$KNOX_HOME/bin/gateway.sh restart
$KYUUBI_HOME/bin/kyuubi stop && $KYUUBI_HOME/bin/kyuubi start

# 3. 启动实时监控
./debug-realtime-monitor.sh &

# 4. 启动调试控制台
./debug-console.sh
EOF

chmod +x start-debug.sh
```

## 📋 调试检查清单

使用以下清单系统地调试问题：

- [ ] 启用详细日志记录
- [ ] 验证服务进程状态
- [ ] 检查端口监听情况
- [ ] 测试基础网络连通性
- [ ] 验证配置文件正确性
- [ ] 监控HTTP请求流
- [ ] 分析URL重写过程
- [ ] 检查错误日志模式
- [ ] 导出完整调试信息
- [ ] 使用交互式调试工具

通过这些调试方法，你应该能够准确定位Knox-Kyuubi集成中的任何问题！