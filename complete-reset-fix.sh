#!/bin/bash

# Knox-Kyuubi完全重置修复脚本
# 从零开始重新配置，彻底解决Service connectivity error

echo "==================================================================="
echo "          Knox-Kyuubi完全重置修复脚本"
echo "          警告：此脚本将重置所有相关配置"
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

# 确认操作
read -p "这将重置Knox和Kyuubi配置，是否继续？(y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo "步骤1: 停止所有服务并清理..."
log_info "停止Knox服务..."
cd "$KNOX_HOME"
bin/gateway.sh stop 2>/dev/null || true
sleep 3

log_info "停止Kyuubi服务..."
KYUUBI_PIDS=$(ps -ef | grep KyuubiServer | grep -v grep | awk '{print $2}')
for pid in $KYUUBI_PIDS; do
    log_info "停止Kyuubi进程 $pid"
    kill $pid 2>/dev/null || true
done
sleep 5

# 强制杀死残留进程
pkill -f KyuubiServer 2>/dev/null || true
pkill -f knox 2>/dev/null || true

echo ""
echo "步骤2: 备份现有配置..."
BACKUP_DIR="$HOME/knox-kyuubi-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -f "$KNOX_HOME/conf/topologies/emr.xml" ]; then
    cp "$KNOX_HOME/conf/topologies/emr.xml" "$BACKUP_DIR/"
fi

if [ -f "$KYUUBI_HOME/conf/kyuubi-defaults.conf" ]; then
    cp "$KYUUBI_HOME/conf/kyuubi-defaults.conf" "$BACKUP_DIR/"
fi

log_info "配置已备份到: $BACKUP_DIR"

echo ""
echo "步骤3: 完全重新配置Kyuubi..."

# 创建全新的Kyuubi配置
cat > "$KYUUBI_HOME/conf/kyuubi-defaults.conf" << 'EOF'
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Kyuubi Configuration
#

## Server
kyuubi.frontend.bind.host                   0.0.0.0
kyuubi.frontend.bind.port                   10099
kyuubi.frontend.protocols                   HTTP

## Authentication
kyuubi.authentication                       NONE

## Session Management
kyuubi.session.idle.timeout                 PT8H
kyuubi.session.check.interval               PT5M

## Engine
kyuubi.engine.type                          SPARK_SQL
kyuubi.engine.ui.enabled                    true

## Logging
kyuubi.frontend.log.level                   INFO
kyuubi.operation.log.dir.root               $KYUUBI_HOME/logs

## Spark Engine specific
kyuubi.engine.spark.main.resource           spark-internal

## Frontend specific
kyuubi.frontend.max.connections             1000
kyuubi.frontend.connection.timeout          300000
kyuubi.frontend.worker.threads              200

EOF

log_success "Kyuubi配置已重新创建"

echo ""
echo "步骤4: 启动Kyuubi并验证..."

cd "$KYUUBI_HOME"
log_info "启动Kyuubi服务..."

# 清理旧日志
rm -f logs/kyuubi-server.log 2>/dev/null || true

# 启动Kyuubi
nohup bin/kyuubi > logs/kyuubi-startup.log 2>&1 &
KYUUBI_PID=$!
log_info "Kyuubi已启动，PID: $KYUUBI_PID"

# 等待Kyuubi完全启动
log_info "等待Kyuubi完全启动..."
for i in {1..60}; do
    if curl -s http://localhost:10099 > /dev/null 2>&1; then
        log_success "Kyuubi已成功启动并可访问"
        break
    fi
    if [ $i -eq 60 ]; then
        log_error "Kyuubi启动超时"
        echo "检查Kyuubi日志:"
        tail -20 "$KYUUBI_HOME/logs/kyuubi-startup.log"
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""

# 验证Kyuubi WebUI
log_info "验证Kyuubi WebUI..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:10099 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    log_success "Kyuubi WebUI响应正常 (HTTP: $HTTP_CODE)"
else
    log_error "Kyuubi WebUI响应异常 (HTTP: $HTTP_CODE)"
    exit 1
fi

echo ""
echo "步骤5: 完全重新配置Knox..."

cd "$KNOX_HOME"

# 清理所有相关的Knox配置
log_info "清理Knox相关配置..."
rm -rf data/services/kyuubiui 2>/dev/null || true
rm -rf data/deployments/*emr* 2>/dev/null || true

# 创建服务定义目录
mkdir -p data/services/kyuubiui/1.9.0

log_info "创建Knox服务定义..."

# 创建service.xml
cat > data/services/kyuubiui/1.9.0/service.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!--
   Licensed to the Apache Software Foundation (ASF) under one or more
   contributor license agreements.  See the NOTICE file distributed with
   this work for additional information regarding copyright ownership.
   The ASF licenses this file to You under the Apache License, Version 2.0
   (the "License"); you may not use this file except in compliance with
   the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-->
<service role="KYUUBIUI" name="kyuubiui" version="1.9.0">
    <metadata>
        <type>UI</type>
        <context>/kyuubi</context>
        <shortDesc>Apache Kyuubi WebUI</shortDesc>
        <description>Apache Kyuubi unified analytics gateway WebUI</description>
    </metadata>
    <policies>
        <policy role="webappsec"/>
        <policy role="authentication" name="Anonymous"/>
        <policy role="rewrite"/>
        <policy role="authorization"/>
    </policies>
    <routes>
        <route path="/kyuubi">
            <rewrite apply="KYUUBIUI/kyuubi/inbound/root" to="request.url"/>
        </route>
        <route path="/kyuubi/**">
            <rewrite apply="KYUUBIUI/kyuubi/inbound/path" to="request.url"/>
        </route>
    </routes>
    <dispatch classname="org.apache.knox.gateway.dispatch.DefaultDispatch"/>
</service>
EOF

# 创建rewrite.xml
cat > data/services/kyuubiui/1.9.0/rewrite.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!--
   Licensed to the Apache Software Foundation (ASF) under one or more
   contributor license agreements.  See the NOTICE file distributed with
   this work for additional information regarding copyright ownership.
   The ASF licenses this file to You under the Apache License, Version 2.0
   (the "License"); you may not use this file except in compliance with
   the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-->
<rules>
    <!-- Inbound rules - rewrite Knox URLs to Kyuubi URLs -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/root" pattern="*://*:*/**/kyuubi">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/"/>
    </rule>
    
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/path" pattern="*://*:*/**/kyuubi/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/{**}"/>
    </rule>

    <!-- Outbound rules - rewrite Kyuubi responses -->
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/headers" pattern="Location: {scheme}://{host}:{port}/{**}">
        <rewrite template="Location: {$frontend[url]}/kyuubi/{**}"/>
    </rule>
    
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/html" pattern="/ui/{**}">
        <rewrite template="{$frontend[url]}/kyuubi/ui/{**}"/>
    </rule>
    
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/css" pattern="href=&quot;/{**}&quot;">
        <rewrite template="href=&quot;{$frontend[url]}/kyuubi/{**}&quot;"/>
    </rule>
    
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/js" pattern="src=&quot;/{**}&quot;">
        <rewrite template="src=&quot;{$frontend[url]}/kyuubi/{**}&quot;"/>
    </rule>
</rules>
EOF

log_success "Knox服务定义已创建"

echo ""
echo "步骤6: 创建全新的topology配置..."

# 创建最简单有效的topology配置
cat > conf/topologies/emr.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!--
   Licensed to the Apache Software Foundation (ASF) under one or more
   contributor license agreements.  See the NOTICE file distributed with
   this work for additional information regarding copyright ownership.
   The ASF licenses this file to You under the Apache License, Version 2.0
   (the "License"); you may not use this file except in compliance with
   the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-->
<topology>
    <gateway>
        <!-- Anonymous authentication for testing -->
        <provider>
            <role>authentication</role>
            <name>Anonymous</name>
            <enabled>true</enabled>
        </provider>

        <!-- Simple authorization -->
        <provider>
            <role>authorization</role>
            <name>AclsAuthz</name>
            <enabled>true</enabled>
            <param>
                <name>knox.acl</name>
                <value>*;*;*</value>
            </param>
        </provider>

        <!-- Web security -->
        <provider>
            <role>webappsec</role>
            <name>WebAppSec</name>
            <enabled>true</enabled>
            <param>
                <name>xframe</name>
                <value>SAMEORIGIN</value>
            </param>
        </provider>

        <!-- Identity assertion -->
        <provider>
            <role>identity-assertion</role>
            <name>Default</name>
            <enabled>true</enabled>
        </provider>
    </gateway>

    <!-- Kyuubi WebUI service -->
    <service>
        <role>KYUUBIUI</role>
        <url>http://localhost:10099</url>
        <param>
            <name>httpclient.connectionTimeout</name>
            <value>60000</value>
        </param>
        <param>
            <name>httpclient.socketTimeout</name>
            <value>60000</value>
        </param>
        <param>
            <name>httpclient.maxRetryCount</name>
            <value>3</value>
        </param>
    </service>
</topology>
EOF

log_success "新的topology配置已创建"

echo ""
echo "步骤7: 启动Knox并进行全面测试..."

log_info "清理Knox日志..."
rm -f logs/gateway.log 2>/dev/null || true

log_info "启动Knox服务..."
bin/gateway.sh start

if [ $? -ne 0 ]; then
    log_error "Knox启动失败"
    exit 1
fi

# 等待Knox启动
log_info "等待Knox完全启动..."
for i in {1..30}; do
    if curl -k -s https://localhost:8443 > /dev/null 2>&1; then
        log_success "Knox已成功启动"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "Knox启动超时"
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""

echo ""
echo "步骤8: 全面连接测试..."

log_info "测试1: Kyuubi直接访问"
KYUUBI_DIRECT=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:10099 2>/dev/null)
if [ "$KYUUBI_DIRECT" = "200" ] || [ "$KYUUBI_DIRECT" = "302" ]; then
    log_success "✅ Kyuubi直接访问正常 (HTTP: $KYUUBI_DIRECT)"
else
    log_error "❌ Kyuubi直接访问失败 (HTTP: $KYUUBI_DIRECT)"
fi

log_info "测试2: Knox基础访问"
KNOX_BASE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null)
if [ "$KNOX_BASE" = "200" ] || [ "$KNOX_BASE" = "404" ]; then
    log_success "✅ Knox基础访问正常 (HTTP: $KNOX_BASE)"
else
    log_error "❌ Knox基础访问失败 (HTTP: $KNOX_BASE)"
fi

log_info "测试3: Knox代理Kyuubi访问"
KNOX_PROXY=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/gateway/emr/kyuubi/ 2>/dev/null)
log_info "Knox代理访问状态码: $KNOX_PROXY"

if [ "$KNOX_PROXY" = "200" ] || [ "$KNOX_PROXY" = "302" ]; then
    log_success "✅ Knox代理访问成功！"
else
    log_warn "⚠️  Knox代理访问状态: $KNOX_PROXY"
    log_info "检查Knox日志中的错误..."
    if [ -f "logs/gateway.log" ]; then
        echo "最近的错误:"
        tail -10 logs/gateway.log | grep -i "error\|exception" | tail -3
    fi
fi

echo ""
echo "步骤9: 详细的连接验证..."

log_info "使用curl详细测试Knox代理..."
echo "执行: curl -k -v https://localhost:8443/gateway/emr/kyuubi/"
curl -k -v https://localhost:8443/gateway/emr/kyuubi/ 2>&1 | head -20

echo ""
echo "==================================================================="
echo "                     重置修复完成！"
echo "==================================================================="

echo ""
echo "📊 测试结果摘要:"
echo "  Kyuubi直接访问: $KYUUBI_DIRECT"
echo "  Knox基础访问:   $KNOX_BASE"
echo "  Knox代理访问:   $KNOX_PROXY"

echo ""
echo "🌐 访问地址:"
echo "  Kyuubi直接访问: http://localhost:10099"
echo "  Knox代理访问:   https://localhost:8443/gateway/emr/kyuubi/"

echo ""
echo "📁 配置文件位置:"
echo "  Kyuubi配置:   $KYUUBI_HOME/conf/kyuubi-defaults.conf"
echo "  Knox Topology: $KNOX_HOME/conf/topologies/emr.xml"
echo "  Knox服务定义: $KNOX_HOME/data/services/kyuubiui/1.9.0/"

echo ""
echo "📋 如果仍有问题，检查以下日志:"
echo "  Knox日志:     $KNOX_HOME/logs/gateway.log"
echo "  Kyuubi日志:   $KYUUBI_HOME/logs/kyuubi-server.log"

echo ""
if [ "$KNOX_PROXY" = "200" ] || [ "$KNOX_PROXY" = "302" ]; then
    log_success "🎉 恭喜！Knox-Kyuubi集成配置成功！"
else
    log_warn "⚠️  集成可能仍有问题，请检查日志并尝试再次访问"
fi

echo "==================================================================="