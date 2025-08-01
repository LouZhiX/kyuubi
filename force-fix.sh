#!/bin/bash

# Knox-Kyuubi强制修复脚本
# 解决所有已知的连接性问题

echo "==================================================================="
echo "              Knox-Kyuubi 强制修复脚本"
echo "==================================================================="

# 设置路径变量
KNOX_HOME="/Users/junglelou/Downloads/knox-1.6.1.2"
KYUUBI_HOME="/Users/junglelou/Downloads/apache-kyuubi-1.9.2-bin"

echo "步骤1: 停止所有服务..."
cd "$KNOX_HOME"
bin/gateway.sh stop 2>/dev/null || true

# 检查并停止Kyuubi
KYUUBI_PID=$(ps -ef | grep KyuubiServer | grep -v grep | awk '{print $2}')
if [ ! -z "$KYUUBI_PID" ]; then
    echo "停止Kyuubi进程 $KYUUBI_PID"
    kill $KYUUBI_PID
    sleep 5
fi

echo "步骤2: 清理和重新配置Kyuubi..."
# 确保Kyuubi配置正确
KYUUBI_CONF="$KYUUBI_HOME/conf/kyuubi-defaults.conf"

# 备份原配置
if [ -f "$KYUUBI_CONF" ]; then
    cp "$KYUUBI_CONF" "$KYUUBI_CONF.backup.$(date +%Y%m%d_%H%M%S)"
fi

# 创建新的Kyuubi配置
cat > "$KYUUBI_CONF" << 'EOF'
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

# Kyuubi server configuration

# 启用WebUI
kyuubi.frontend.bind.host=0.0.0.0
kyuubi.frontend.bind.port=10099
kyuubi.frontend.protocols=HTTP

# 启用WebUI功能
kyuubi.engine.ui.enabled=true

# Session配置
kyuubi.session.idle.timeout=PT8H
kyuubi.session.check.interval=PT1H

# 日志配置
kyuubi.frontend.log.level=INFO

EOF

echo "步骤3: 重新启动Kyuubi..."
cd "$KYUUBI_HOME"
nohup bin/kyuubi > logs/kyuubi-startup.log 2>&1 &
KYUUBI_PID=$!
echo "Kyuubi启动中，PID: $KYUUBI_PID"

# 等待Kyuubi启动
echo "等待Kyuubi完全启动..."
for i in {1..30}; do
    if curl -s http://localhost:10099 > /dev/null 2>&1; then
        echo "✅ Kyuubi已成功启动"
        break
    fi
    echo "等待中... ($i/30)"
    sleep 2
done

# 验证Kyuubi是否正常运行
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:10099 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "✅ Kyuubi WebUI验证成功 (HTTP: $HTTP_CODE)"
else
    echo "❌ Kyuubi WebUI验证失败 (HTTP: $HTTP_CODE)"
    echo "检查Kyuubi日志:"
    tail -10 "$KYUUBI_HOME/logs/kyuubi-server.log" 2>/dev/null || echo "日志文件不存在"
    exit 1
fi

echo "步骤4: 重新配置Knox..."
cd "$KNOX_HOME"

# 清理旧的服务定义
rm -rf data/services/kyuubiui 2>/dev/null || true

# 创建新的服务定义目录
mkdir -p data/services/kyuubiui/1.9.0

echo "步骤5: 创建正确的service.xml..."
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

echo "步骤6: 创建正确的rewrite.xml..."
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
    <!-- 入站重写规则 - 将Knox URL重写为Kyuubi URL -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/root" pattern="*://*:*/**/kyuubi">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/"/>
    </rule>
    
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/path" pattern="*://*:*/**/kyuubi/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/{**}"/>
    </rule>

    <!-- 出站重写规则 - 将Kyuubi响应中的URL重写为Knox URL -->
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/headers" pattern="Location: {scheme}://{host}:{port}/{**}">
        <rewrite template="Location: {$frontend[url]}/kyuubi/{**}"/>
    </rule>
    
    <!-- 静态资源重写 -->
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/html" pattern="/ui/{**}">
        <rewrite template="{$frontend[url]}/kyuubi/ui/{**}"/>
    </rule>
</rules>
EOF

echo "步骤7: 创建正确的topology配置..."
# 备份原topology
cp conf/topologies/emr.xml conf/topologies/emr.xml.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

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
        <!-- 使用匿名认证简化测试 -->
        <provider>
            <role>authentication</role>
            <name>Anonymous</name>
            <enabled>true</enabled>
        </provider>

        <!-- 授权配置 -->
        <provider>
            <role>authorization</role>
            <name>AclsAuthz</name>
            <enabled>true</enabled>
            <param>
                <name>knox.acl</name>
                <value>*;*;*</value>
            </param>
        </provider>

        <!-- Web应用安全配置 -->
        <provider>
            <role>webappsec</role>
            <name>WebAppSec</name>
            <enabled>true</enabled>
            <param>
                <name>xframe</name>
                <value>SAMEORIGIN</value>
            </param>
        </provider>

        <!-- 身份断言配置 -->
        <provider>
            <role>identity-assertion</role>
            <name>Default</name>
            <enabled>true</enabled>
        </provider>
    </gateway>

    <!-- Kyuubi WebUI服务配置 -->
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

echo "步骤8: 启动Knox服务..."
bin/gateway.sh start

echo "步骤9: 等待Knox完全启动..."
sleep 15

echo "步骤10: 验证修复结果..."
echo "--- 测试Kyuubi直接访问 ---"
KYUUBI_DIRECT=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:10099)
echo "Kyuubi直接访问状态码: $KYUUBI_DIRECT"

echo "--- 测试Knox代理访问 ---"
KNOX_PROXY=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/gateway/emr/kyuubi/)
echo "Knox代理访问状态码: $KNOX_PROXY"

echo ""
echo "==================================================================="
echo "修复完成！"
echo ""
echo "访问地址："
echo "  Kyuubi直接访问: http://localhost:10099"
echo "  Knox代理访问:   https://localhost:8443/gateway/emr/kyuubi/"
echo ""

if [ "$KYUUBI_DIRECT" = "200" ] || [ "$KYUUBI_DIRECT" = "302" ]; then
    echo "✅ Kyuubi直接访问正常"
else
    echo "❌ Kyuubi直接访问异常"
fi

if [ "$KNOX_PROXY" = "200" ] || [ "$KNOX_PROXY" = "302" ]; then
    echo "✅ Knox代理访问正常"
else
    echo "❌ Knox代理访问异常"
    echo "检查Knox日志:"
    tail -5 logs/gateway.log
fi

echo "==================================================================="