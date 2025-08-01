#!/bin/bash

# Knox-Kyuubi深度诊断脚本
# 专门解决持续的连接性问题

echo "==================================================================="
echo "              Knox-Kyuubi 深度诊断脚本"
echo "==================================================================="

# 设置路径变量
KNOX_HOME="/Users/junglelou/Downloads/knox-1.6.1.2"
KYUUBI_HOME="/Users/junglelou/Downloads/apache-kyuubi-1.9.2-bin"

echo "步骤1: 检查当前服务状态..."
echo "--- Kyuubi进程状态 ---"
ps -ef | grep KyuubiServer | grep -v grep

echo "--- Knox进程状态 ---"
ps -ef | grep knox | grep -v grep

echo ""
echo "步骤2: 检查端口监听状态..."
echo "--- 检查Kyuubi端口10099 ---"
lsof -i :10099 || echo "端口10099未被监听"

echo "--- 检查Knox端口8443 ---"
lsof -i :8443 || echo "端口8443未被监听"

echo ""
echo "步骤3: 测试网络连接..."
echo "--- 测试Kyuubi直接连接 ---"
echo "GET /" | nc localhost 10099 2>/dev/null && echo "端口10099可达" || echo "端口10099不可达"

echo "--- 测试Kyuubi HTTP响应 ---"
HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:10099 2>/dev/null)
echo "Kyuubi HTTP响应码: $HTTP_RESPONSE"

if [ "$HTTP_RESPONSE" != "200" ] && [ "$HTTP_RESPONSE" != "302" ]; then
    echo "❌ Kyuubi WebUI响应异常"
    echo "尝试检查Kyuubi配置..."
    
    if [ -f "$KYUUBI_HOME/conf/kyuubi-defaults.conf" ]; then
        echo "--- Kyuubi配置检查 ---"
        grep -E "(frontend|bind|port)" "$KYUUBI_HOME/conf/kyuubi-defaults.conf" || echo "未找到WebUI配置"
    fi
else
    echo "✅ Kyuubi WebUI响应正常"
fi

echo ""
echo "步骤4: 检查Knox配置..."
echo "--- 检查topology文件 ---"
TOPOLOGY_FILE="$KNOX_HOME/conf/topologies/emr.xml"
if [ -f "$TOPOLOGY_FILE" ]; then
    echo "✅ 找到topology文件"
    if grep -q "KYUUBIUI" "$TOPOLOGY_FILE"; then
        echo "✅ topology包含KYUUBIUI配置"
        echo "配置的URL:"
        grep -A2 -B2 "KYUUBIUI" "$TOPOLOGY_FILE"
    else
        echo "❌ topology缺少KYUUBIUI配置"
    fi
else
    echo "❌ 找不到topology文件"
fi

echo ""
echo "--- 检查服务定义 ---"
SERVICE_DIR="$KNOX_HOME/data/services/kyuubiui"
if [ -d "$SERVICE_DIR" ]; then
    echo "✅ 找到服务定义目录"
    ls -la "$SERVICE_DIR/"
    if [ -f "$SERVICE_DIR/1.9.0/service.xml" ]; then
        echo "✅ 找到service.xml"
    else
        echo "❌ 缺少service.xml"
    fi
    if [ -f "$SERVICE_DIR/1.9.0/rewrite.xml" ]; then
        echo "✅ 找到rewrite.xml"
    else
        echo "❌ 缺少rewrite.xml"
    fi
else
    echo "❌ 找不到服务定义目录"
fi

echo ""
echo "步骤5: 检查Knox日志中的具体错误..."
echo "--- 最近的Knox错误 ---"
if [ -f "$KNOX_HOME/logs/gateway.log" ]; then
    echo "最近5条错误信息:"
    tail -100 "$KNOX_HOME/logs/gateway.log" | grep -i "error\|exception" | tail -5
    echo ""
    echo "KYUUBIUI相关日志:"
    tail -100 "$KNOX_HOME/logs/gateway.log" | grep -i "kyuubi" | tail -3
else
    echo "找不到Knox日志文件"
fi

echo ""
echo "步骤6: 尝试手动测试连接..."
echo "--- 测试Knox到Kyuubi的连接 ---"
# 模拟Knox的HTTP请求
echo "使用curl模拟Knox请求:"
curl -v -H "User-Agent: Apache-Knox-Gateway" http://localhost:10099 2>&1 | head -10

echo ""
echo "步骤7: 检查Knox部署状态..."
if [ -d "$KNOX_HOME/data/deployments" ]; then
    echo "--- Knox部署目录 ---"
    ls -la "$KNOX_HOME/data/deployments/" | grep emr
fi

echo ""
echo "==================================================================="
echo "诊断完成！根据以上信息，问题可能出现在："
echo "1. Kyuubi WebUI配置问题"
echo "2. Knox服务定义缺失或错误"
echo "3. 网络连接问题"
echo "4. Knox到Kyuubi的URL映射错误"
echo "==================================================================="

# 生成修复建议
echo ""
echo "自动修复建议："

if [ "$HTTP_RESPONSE" != "200" ] && [ "$HTTP_RESPONSE" != "302" ]; then
    echo "❌ 需要修复Kyuubi WebUI配置"
    echo "建议执行："
    echo "  1. 检查Kyuubi配置文件"
    echo "  2. 确保WebUI已启用"
    echo "  3. 重启Kyuubi服务"
fi

if [ ! -d "$SERVICE_DIR" ]; then
    echo "❌ 需要创建Knox服务定义"
    echo "建议执行："
    echo "  1. 创建服务定义目录"
    echo "  2. 部署service.xml和rewrite.xml"
    echo "  3. 重启Knox服务"
fi

echo ""
echo "现在开始自动修复..."