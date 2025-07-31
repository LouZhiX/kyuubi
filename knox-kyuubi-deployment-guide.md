# Knox与Kyuubi WebUI集成部署指南

本指南说明如何配置Apache Knox来代理Apache Kyuubi的WebUI，实现统一的Web访问入口和安全控制。

## 概述

Apache Knox是一个REST API网关，为Apache Hadoop集群提供单点访问。通过配置Knox来代理Kyuubi WebUI，可以实现：

- 统一的Web访问入口
- 集中的认证和授权管理
- SSL/TLS终结
- 负载均衡和高可用
- 审计日志记录

## 前提条件

1. Apache Knox已安装并运行
2. Apache Kyuubi已安装并启用WebUI（默认端口10099）
3. 网络连通性：Knox服务器能够访问Kyuubi服务器

## 部署步骤

### 1. 创建Kyuubi服务定义

在Knox的服务定义目录中创建Kyuubi服务配置：

```bash
# 创建服务定义目录
mkdir -p $KNOX_HOME/data/services/kyuubi/1.0.0

# 复制服务定义文件
cp knox-kyuubi-service.xml $KNOX_HOME/data/services/kyuubi/1.0.0/service.xml
cp knox-kyuubi-rewrite.xml $KNOX_HOME/data/services/kyuubi/1.0.0/rewrite.xml
```

### 2. 配置Knox拓扑

创建或修改Knox拓扑文件（例如：`$KNOX_HOME/conf/topologies/kyuubi.xml`）：

```bash
cp knox-topology-example.xml $KNOX_HOME/conf/topologies/kyuubi.xml
```

**重要配置项说明：**

- **Kyuubi服务URL**：修改`<url>`标签中的主机名和端口
  ```xml
  <service>
      <role>KYUUBI</role>
      <url>http://your-kyuubi-server:10099</url>
  </service>
  ```

- **认证配置**：根据你的环境配置LDAP、Kerberos或其他认证方式

- **授权配置**：配置访问控制列表（ACL）

### 3. 验证Kyuubi WebUI配置

确保Kyuubi服务器的WebUI已启用：

```bash
# 检查Kyuubi配置文件
vi $KYUUBI_HOME/conf/kyuubi-defaults.conf

# 确保以下配置项已设置（如果需要）
# kyuubi.frontend.rest.bind.host=0.0.0.0
# kyuubi.frontend.rest.bind.port=10099
# kyuubi.frontend.protocols=THRIFT_BINARY,REST
```

### 4. 重启Knox服务

```bash
# 停止Knox
$KNOX_HOME/bin/gateway.sh stop

# 启动Knox
$KNOX_HOME/bin/gateway.sh start

# 检查Knox日志
tail -f $KNOX_HOME/logs/gateway.log
```

### 5. 测试访问

通过Knox访问Kyuubi WebUI：

```
https://knox-gateway-host:8443/gateway/kyuubi/kyuubi/
```

## 配置详解

### service.xml配置说明

```xml
<service role="KYUUBI" name="kyuubi" version="1.0.0">
    <policies>
        <!-- 启用Web应用安全策略 -->
        <policy role="webappsec"/>
        <!-- 匿名认证（可根据需要修改） -->
        <policy role="authentication" name="Anonymous"/>
        <!-- 启用URL重写 -->
        <policy role="rewrite"/>
        <!-- 启用授权 -->
        <policy role="authorization"/>
    </policies>
    <routes>
        <!-- 定义路由规则，匹配/kyuubi路径 -->
        <route path="/kyuubi">
            <!-- 应用响应头重写 -->
            <rewrite apply="KYUUBI/kyuubi/outbound/headers" to="response.headers"/>
            <!-- 应用HTML内容重写 -->
            <rewrite apply="KYUUBI/kyuubi/outbound/html" to="response.body"/>
        </route>
        <!-- 其他路由规则... -->
    </routes>
    <!-- 使用PassAllHeadersDispatch确保正确的头部处理 -->
    <dispatch classname="org.apache.hadoop.gateway.dispatch.PassAllHeadersDispatch"/>
</service>
```

### rewrite.xml配置说明

重写规则分为两类：

1. **入站规则（Inbound）**：将Knox接收的URL重写为后端服务URL
2. **出站规则（Outbound）**：重写响应内容中的URL引用

关键重写规则：

```xml
<!-- 入站：将/kyuubi路径重写为后端服务URL -->
<rule dir="IN" name="KYUUBI/kyuubi/inbound/path" pattern="*://*:*/**/kyuubi/{path=**}?{**}">
    <rewrite template="{$serviceUrl[KYUUBI]}/{path=**}?{**}"/>
</rule>

<!-- 出站：重写静态资源路径 -->
<rule dir="OUT" name="KYUUBI/kyuubi/outbound/assets" pattern="/assets/{**}">
    <rewrite template="{$frontend[path]}/kyuubi/assets/{**}"/>
</rule>
```

## 高级配置

### 1. 启用HTTPS

修改拓扑配置，将服务URL改为HTTPS：

```xml
<service>
    <role>KYUUBI</role>
    <url>https://your-kyuubi-server:10099</url>
</service>
```

### 2. 配置负载均衡

对于高可用部署，可以配置多个Kyuubi服务实例：

```xml
<service>
    <role>KYUUBI</role>
    <url>http://kyuubi-server1:10099</url>
</service>
<service>
    <role>KYUUBI</role>
    <url>http://kyuubi-server2:10099</url>
</service>
```

### 3. 自定义认证

替换Anonymous认证为LDAP或Kerberos：

```xml
<provider>
    <role>authentication</role>
    <name>ShiroProvider</name>
    <enabled>true</enabled>
    <!-- LDAP配置参数... -->
</provider>
```

### 4. 配置授权规则

添加基于用户或组的访问控制：

```xml
<provider>
    <role>authorization</role>
    <name>AclsAuthz</name>
    <enabled>true</enabled>
    <param>
        <name>kyuubi.acl</name>
        <value>admin;*;*</value>
    </param>
</provider>
```

## 故障排除

### 1. 检查服务状态

```bash
# 检查Knox状态
$KNOX_HOME/bin/gateway.sh status

# 检查Kyuubi状态
$KYUUBI_HOME/bin/kyuubi status
```

### 2. 查看日志

```bash
# Knox日志
tail -f $KNOX_HOME/logs/gateway.log
tail -f $KNOX_HOME/logs/gateway-audit.log

# Kyuubi日志
tail -f $KYUUBI_HOME/logs/kyuubi-server-*.log
```

### 3. 常见问题

**问题1：404 Not Found**
- 检查服务定义文件路径是否正确
- 验证拓扑配置中的服务URL
- 确认Kyuubi WebUI已启用

**问题2：静态资源加载失败**
- 检查rewrite.xml中的静态资源重写规则
- 验证Content-Type匹配规则

**问题3：认证失败**
- 检查认证提供者配置
- 验证用户凭据和权限设置

## 安全建议

1. **启用HTTPS**：在生产环境中始终使用HTTPS
2. **强认证**：使用LDAP、Kerberos或其他强认证机制
3. **访问控制**：配置细粒度的授权规则
4. **审计日志**：启用并监控访问日志
5. **网络隔离**：使用防火墙限制网络访问

## 总结

通过以上配置，您可以成功地将Kyuubi WebUI集成到Knox网关中，实现统一的Web访问入口和安全控制。根据您的具体环境和需求，可以进一步调整认证、授权和其他安全配置。