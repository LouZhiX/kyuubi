#!/bin/bash

#
# Kyuubi 1.9.2 快速功能验证脚本
# 用于快速验证Kyuubi的核心功能是否正常
#

# 配置参数
KYUUBI_HOME=${KYUUBI_HOME:-/opt/kyuubi}
TEST_USER=${TEST_USER:-testuser}
KYUUBI_HOST=${KYUUBI_HOST:-localhost}
KYUUBI_THRIFT_PORT=${KYUUBI_THRIFT_PORT:-10009}

echo "=== Kyuubi 1.9.2 快速功能验证 ==="
echo "Kyuubi Home: $KYUUBI_HOME"
echo "测试用户: $TEST_USER"
echo "服务地址: $KYUUBI_HOST:$KYUUBI_THRIFT_PORT"
echo ""

# 1. 检查Kyuubi服务状态
echo "1. 检查Kyuubi服务状态..."
if $KYUUBI_HOME/bin/kyuubi status; then
    echo "✓ Kyuubi服务正在运行"
else
    echo "✗ Kyuubi服务未运行，尝试启动..."
    $KYUUBI_HOME/bin/kyuubi start
    sleep 10
fi

# 2. 测试JDBC连接
echo ""
echo "2. 测试JDBC连接..."
if timeout 20 $KYUUBI_HOME/bin/beeline -u "jdbc:hive2://$KYUUBI_HOST:$KYUUBI_THRIFT_PORT" -n "$TEST_USER" -e "SELECT 1 as test_connection;" 2>/dev/null | grep -q "test_connection"; then
    echo "✓ JDBC连接成功"
else
    echo "✗ JDBC连接失败"
    exit 1
fi

# 3. 测试基本SQL功能
echo ""
echo "3. 测试基本SQL功能..."
SQL_TEST="
CREATE DATABASE IF NOT EXISTS quick_test;
USE quick_test;
CREATE TABLE IF NOT EXISTS sample_table (id INT, name STRING) USING PARQUET;
INSERT OVERWRITE sample_table VALUES (1, 'test');
SELECT COUNT(*) as record_count FROM sample_table;
"

if timeout 30 $KYUUBI_HOME/bin/beeline -u "jdbc:hive2://$KYUUBI_HOST:$KYUUBI_THRIFT_PORT" -n "$TEST_USER" -e "$SQL_TEST" 2>/dev/null | grep -q "record_count"; then
    echo "✓ 基本SQL功能正常"
else
    echo "✗ 基本SQL功能异常"
    exit 1
fi

# 4. 检查引擎管理
echo ""
echo "4. 检查引擎管理功能..."
if $KYUUBI_HOME/bin/kyuubi-ctl list engine >/dev/null 2>&1; then
    echo "✓ 引擎管理功能可用"
else
    echo "✗ 引擎管理功能不可用"
fi

# 5. 检查REST API
echo ""
echo "5. 检查REST API..."
if curl -s -f "http://$KYUUBI_HOST:10099/api/v1/server/info" >/dev/null 2>&1; then
    echo "✓ REST API可用"
else
    echo "⚠ REST API不可用 (可能未启用)"
fi

echo ""
echo "=== 快速验证完成 ==="
echo "✓ Kyuubi 1.9.2 基本功能正常，可以进行详细测试"
echo ""
echo "运行完整测试套件："
echo "  ./kyuubi-test-runner.sh"
echo ""