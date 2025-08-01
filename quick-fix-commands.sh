#!/bin/bash

# Knox-Kyuubi快速修复脚本
# 基于用户当前的macOS环境

echo "==================================================================="
echo "              Knox-Kyuubi WebUI 快速修复脚本"
echo "==================================================================="

# 设置路径变量
KNOX_HOME="/Users/junglelou/Downloads/knox-1.6.1.2"
KYUUBI_HOME="/Users/junglelou/Downloads/apache-kyuubi-1.9.2-bin"

echo "步骤1: 停止Knox服务..."
cd "$KNOX_HOME"
bin/gateway.sh stop

echo "步骤2: 创建KYUUBIUI服务定义目录..."
mkdir -p "$KNOX_HOME/data/services/kyuubiui/1.9.0"

echo "步骤3: 创建service.xml..."
cat > "$KNOX_HOME/data/services/kyuubiui/1.9.0/service.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
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

echo "步骤4: 创建rewrite.xml..."
cat > "$KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<rules>
    <!-- 入站重写规则 -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/root" pattern="*://*:*/**/kyuubi">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/"/>
    </rule>
    
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/path" pattern="*://*:*/**/kyuubi/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/{**}"/>
    </rule>

    <!-- 出站重写规则 -->
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/headers" pattern="Location: {scheme}://{host}:{port}/{**}">
        <rewrite template="Location: {$frontend[url]}/kyuubi/{**}"/>
    </rule>
</rules>
EOF

echo "步骤5: 备份原始emr.xml..."
cp "$KNOX_HOME/conf/topologies/emr.xml" "$KNOX_HOME/conf/topologies/emr.xml.backup.$(date +%Y%m%d_%H%M%S)"

echo "步骤6: 更新emr.xml topology配置..."
cat > "$KNOX_HOME/conf/topologies/emr.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<topology>
    <gateway>
        <provider>
            <role>authentication</role>
            <name>Anonymous</name>
            <enabled>true</enabled>
        </provider>

        <provider>
            <role>authorization</role>
            <name>AclsAuthz</name>
            <enabled>true</enabled>
            <param>
                <name>knox.acl</name>
                <value>*;*;*</value>
            </param>
        </provider>

        <provider>
            <role>webappsec</role>
            <name>WebAppSec</name>
            <enabled>true</enabled>
            <param>
                <name>xframe</name>
                <value>SAMEORIGIN</value>
            </param>
        </provider>

        <provider>
            <role>identity-assertion</role>
            <name>Default</name>
            <enabled>true</enabled>
        </provider>
    </gateway>

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
    </service>
</topology>
EOF

echo "步骤7: 启动Knox服务..."
bin/gateway.sh start

echo "步骤8: 等待服务启动..."
sleep 10

echo "步骤9: 测试连接..."
echo "正在测试Kyuubi WebUI直接访问..."
curl -s -o /dev/null -w "Kyuubi直接访问 HTTP状态码: %{http_code}\n" http://localhost:10099

echo "正在测试Knox代理访问..."
curl -s -o /dev/null -w "Knox代理访问 HTTP状态码: %{http_code}\n" -k https://localhost:8443/gateway/emr/kyuubi/

echo "==================================================================="
echo "修复完成！"
echo ""
echo "访问地址："
echo "  Kyuubi直接访问: http://localhost:10099"
echo "  Knox代理访问:   https://localhost:8443/gateway/emr/kyuubi/"
echo ""
echo "如果仍有问题，请检查日志："
echo "  Knox日志: $KNOX_HOME/logs/gateway.log"
echo "  Kyuubi日志: $KYUUBI_HOME/logs/kyuubi-server.log"
echo "==================================================================="