#!/bin/bash

#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

# =============================================================================
# Kyuubi 1.9 与 Knox 集成部署脚本
# 
# 功能：
# 1. 部署Kyuubi WebUI服务定义到Knox
# 2. 配置相关的安全和重写规则
# 3. 创建拓扑文件
# 4. 重启Knox服务
# =============================================================================

set -euo pipefail

# 配置变量
KNOX_HOME="${KNOX_HOME:-/opt/knox}"
KYUUBI_HOST="${KYUUBI_HOST:-localhost}"
KYUUBI_WEB_PORT="${KYUUBI_WEB_PORT:-10099}"
KNOX_TOPOLOGY_NAME="${KNOX_TOPOLOGY_NAME:-kyuubi-cluster}"

# 颜色输出
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

# 检查Knox安装
check_knox_installation() {
    log_info "检查Knox安装..."
    
    if [ ! -d "$KNOX_HOME" ]; then
        log_error "Knox安装目录未找到: $KNOX_HOME"
        exit 1
    fi
    
    if [ ! -f "$KNOX_HOME/bin/gateway.sh" ]; then
        log_error "Knox网关脚本未找到: $KNOX_HOME/bin/gateway.sh"
        exit 1
    fi
    
    log_success "Knox安装检查通过"
}

# 创建服务定义目录
create_service_directories() {
    log_info "创建Kyuubi服务定义目录..."
    
    local service_dir="$KNOX_HOME/data/services/kyuubiui/1.9.0"
    
    if [ ! -d "$service_dir" ]; then
        mkdir -p "$service_dir"
        log_success "创建目录: $service_dir"
    else
        log_warn "目录已存在: $service_dir"
    fi
}

# 部署service.xml
deploy_service_xml() {
    log_info "部署Kyuubi service.xml..."
    
    local service_dir="$KNOX_HOME/data/services/kyuubiui/1.9.0"
    local service_file="$service_dir/service.xml"
    
    cat > "$service_file" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<service role="KYUUBIUI" name="kyuubiui" version="1.9.0">
    <policies>
        <policy role="webappsec"/>
        <policy role="authentication" name="Anonymous"/>
        <policy role="rewrite"/>
        <policy role="authorization"/>
    </policies>
    <routes>
        <route path="/kyuubi">
            <rewrite apply="KYUUBIUI/kyuubiui/outbound/links" to="response.body"/>
        </route>
        <route path="/kyuubi/**">
            <rewrite apply="KYUUBIUI/kyuubiui/outbound/links" to="response.body"/>
        </route>
    </routes>
    <dispatch classname="org.apache.hadoop.gateway.dispatch.PassAllHeadersDispatch"/>
</service>
EOF
    
    log_success "service.xml 部署完成: $service_file"
}

# 部署rewrite.xml
deploy_rewrite_xml() {
    log_info "部署Kyuubi rewrite.xml..."
    
    local service_dir="$KNOX_HOME/data/services/kyuubiui/1.9.0"
    local rewrite_file="$service_dir/rewrite.xml"
    
    cat > "$rewrite_file" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<rules>
    <!-- 入站重写规则 -->
    <rule dir="IN" name="KYUUBIUI/kyuubiui/inbound/root" pattern="*://*:*/**/kyuubi/">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/"/>
    </rule>
    
    <rule dir="IN" name="KYUUBIUI/kyuubiui/inbound/path" pattern="*://*:*/**/kyuubi/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/{**}"/>
    </rule>
    
    <rule dir="IN" name="KYUUBIUI/kyuubiui/inbound/api" pattern="*://*:*/**/kyuubi/api/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/api/{**}"/>
    </rule>
    
    <rule dir="IN" name="KYUUBIUI/kyuubiui/inbound/ws" pattern="*://*:*/**/kyuubi/ws/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/ws/{**}"/>
    </rule>
    
    <!-- 出站重写规则 -->
    <rule dir="OUT" name="KYUUBIUI/kyuubiui/outbound/css" pattern="href=&quot;css/{**}&quot;">
        <rewrite template="href=&quot;{$frontend[path]}/kyuubi/css/{**}&quot;"/>
    </rule>
    
    <rule dir="OUT" name="KYUUBIUI/kyuubiui/outbound/js" pattern="src=&quot;js/{**}&quot;">
        <rewrite template="src=&quot;{$frontend[path]}/kyuubi/js/{**}&quot;"/>
    </rule>
    
    <rule dir="OUT" name="KYUUBIUI/kyuubiui/outbound/images" pattern="src=&quot;images/{**}&quot;">
        <rewrite template="src=&quot;{$frontend[path]}/kyuubi/images/{**}&quot;"/>
    </rule>
    
    <rule dir="OUT" name="KYUUBIUI/kyuubiui/outbound/api" pattern="&quot;api/{**}&quot;">
        <rewrite template="&quot;{$frontend[path]}/kyuubi/api/{**}&quot;"/>
    </rule>
    
    <rule dir="OUT" name="KYUUBIUI/kyuubiui/outbound/websocket" pattern="ws://{host}:{port}/ws/{**}">
        <rewrite template="ws://{$frontend[host]}:{$frontend[port]}{$frontend[path]}/kyuubi/ws/{**}"/>
    </rule>
    
    <rule dir="OUT" name="KYUUBIUI/kyuubiui/outbound/websocket-secure" pattern="wss://{host}:{port}/ws/{**}">
        <rewrite template="wss://{$frontend[host]}:{$frontend[port]}{$frontend[path]}/kyuubi/ws/{**}"/>
    </rule>
    
    <!-- 重写过滤器 -->
    <filter name="KYUUBIUI/kyuubiui/outbound/links">
        <content type="text/html">
            <apply path="href=&quot;css/{**}&quot;" rule="KYUUBIUI/kyuubiui/outbound/css"/>
            <apply path="src=&quot;js/{**}&quot;" rule="KYUUBIUI/kyuubiui/outbound/js"/>
            <apply path="src=&quot;images/{**}&quot;" rule="KYUUBIUI/kyuubiui/outbound/images"/>
            <apply path="&quot;api/{**}&quot;" rule="KYUUBIUI/kyuubiui/outbound/api"/>
        </content>
        <content type="application/javascript">
            <apply path="&quot;api/{**}&quot;" rule="KYUUBIUI/kyuubiui/outbound/api"/>
            <apply path="ws://{host}:{port}/ws/{**}" rule="KYUUBIUI/kyuubiui/outbound/websocket"/>
            <apply path="wss://{host}:{port}/ws/{**}" rule="KYUUBIUI/kyuubiui/outbound/websocket-secure"/>
        </content>
        <content type="application/json">
            <apply path="&quot;api/{**}&quot;" rule="KYUUBIUI/kyuubiui/outbound/api"/>
        </content>
    </filter>
    
    <rule dir="OUT" name="KYUUBIUI/kyuubiui/outbound/location" pattern="{scheme}://{host}:{port}/{**}">
        <rewrite template="{$frontend[scheme]}://{$frontend[host]}:{$frontend[port]}{$frontend[path]}/kyuubi/{**}"/>
    </rule>
</rules>
EOF
    
    log_success "rewrite.xml 部署完成: $rewrite_file"
}

# 创建拓扑文件
create_topology() {
    log_info "创建Knox拓扑文件..."
    
    local topology_file="$KNOX_HOME/conf/topologies/$KNOX_TOPOLOGY_NAME.xml"
    
    cat > "$topology_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<topology>
    <gateway>
        <provider>
            <role>authentication</role>
            <name>Anonymous</name>
            <enabled>true</enabled>
        </provider>
        
        <provider>
            <role>identity-assertion</role>
            <name>Default</name>
            <enabled>true</enabled>
        </provider>
        
        <provider>
            <role>hostmap</role>
            <name>static</name>
            <enabled>true</enabled>
            <param>
                <name>localhost</name>
                <value>$KYUUBI_HOST</value>
            </param>
        </provider>
    </gateway>
    
    <service>
        <role>KYUUBIUI</role>
        <url>http://$KYUUBI_HOST:$KYUUBI_WEB_PORT</url>
    </service>
</topology>
EOF
    
    log_success "拓扑文件创建完成: $topology_file"
}

# 验证配置
validate_configuration() {
    log_info "验证配置文件..."
    
    # 检查服务定义文件
    local service_file="$KNOX_HOME/data/services/kyuubiui/1.9.0/service.xml"
    local rewrite_file="$KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml"
    local topology_file="$KNOX_HOME/conf/topologies/$KNOX_TOPOLOGY_NAME.xml"
    
    if [ ! -f "$service_file" ]; then
        log_error "服务定义文件未找到: $service_file"
        return 1
    fi
    
    if [ ! -f "$rewrite_file" ]; then
        log_error "重写规则文件未找到: $rewrite_file"
        return 1
    fi
    
    if [ ! -f "$topology_file" ]; then
        log_error "拓扑文件未找到: $topology_file"
        return 1
    fi
    
    # 使用xmllint验证XML格式（如果可用）
    if command -v xmllint >/dev/null 2>&1; then
        log_info "验证XML文件格式..."
        xmllint --noout "$service_file" 2>/dev/null && log_success "service.xml 格式正确"
        xmllint --noout "$rewrite_file" 2>/dev/null && log_success "rewrite.xml 格式正确"
        xmllint --noout "$topology_file" 2>/dev/null && log_success "topology.xml 格式正确"
    fi
    
    log_success "配置验证完成"
}

# 重启Knox服务
restart_knox() {
    log_info "重启Knox服务..."
    
    # 停止Knox
    if [ -f "$KNOX_HOME/bin/gateway.sh" ]; then
        log_info "停止Knox服务..."
        "$KNOX_HOME/bin/gateway.sh" stop || true
        sleep 5
    fi
    
    # 启动Knox
    log_info "启动Knox服务..."
    "$KNOX_HOME/bin/gateway.sh" start
    
    # 等待服务启动
    log_info "等待Knox服务启动..."
    sleep 10
    
    # 检查服务状态
    if pgrep -f "knox" > /dev/null; then
        log_success "Knox服务启动成功"
    else
        log_error "Knox服务启动失败"
        return 1
    fi
}

# 显示访问信息
show_access_info() {
    log_info "部署完成！访问信息："
    echo
    echo "Kyuubi WebUI通过Knox访问地址："
    echo "  https://knox-gateway:8443/gateway/$KNOX_TOPOLOGY_NAME/kyuubi/"
    echo
    echo "如果使用默认端口，完整URL示例："
    echo "  https://localhost:8443/gateway/$KNOX_TOPOLOGY_NAME/kyuubi/"
    echo
    echo "请确保："
    echo "  1. Kyuubi服务器 ($KYUUBI_HOST:$KYUUBI_WEB_PORT) 正在运行"
    echo "  2. Knox网关服务正在运行"
    echo "  3. 网络连接正常"
    echo "  4. 防火墙规则允许相关端口访问"
    echo
}

# 主函数
main() {
    log_info "开始部署Kyuubi 1.9与Knox集成..."
    echo "配置参数："
    echo "  Knox Home: $KNOX_HOME"
    echo "  Kyuubi Host: $KYUUBI_HOST"
    echo "  Kyuubi Web Port: $KYUUBI_WEB_PORT"
    echo "  Knox Topology: $KNOX_TOPOLOGY_NAME"
    echo
    
    # 执行部署步骤
    check_knox_installation
    create_service_directories
    deploy_service_xml
    deploy_rewrite_xml
    create_topology
    validate_configuration
    restart_knox
    show_access_info
    
    log_success "Kyuubi Knox集成部署完成！"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi