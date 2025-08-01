# Kyuubi WebUI 与 Apache Knox 集成

## 概述

本项目为 Kyuubi 1.9 提供了与 Apache Knox Gateway 的完整集成方案，实现统一的 Web 访问入口和安全管理。

## 功能特性

- ✅ **统一访问入口**: 通过 Knox Gateway 提供统一的 Web 访问入口
- ✅ **安全管理**: 利用 Knox 的认证、授权和安全功能
- ✅ **SSL 终止**: 在 Knox 层处理 SSL，简化后端配置
- ✅ **负载均衡**: 支持多 Kyuubi 实例的负载均衡
- ✅ **健康检查**: 自动监控 Knox Gateway 和 Kyuubi 服务状态
- ✅ **配置管理**: 提供完整的配置模板和部署脚本

## 快速开始

### 1. 环境要求

- Java 8 或更高版本
- Apache Knox 1.6.0 或更高版本
- Kyuubi 1.9.0 或更高版本

### 2. 安装 Knox

```bash
# 下载 Knox
wget https://downloads.apache.org/knox/1.6.0/knox-1.6.0.tar.gz
tar -xzf knox-1.6.0.tar.gz
cd knox-1.6.0

# 设置环境变量
export KNOX_HOME=$(pwd)
```

### 3. 部署集成

使用提供的部署脚本：

```bash
# 设置环境变量
export KNOX_HOME=/path/to/knox
export KYUUBI_HOME=/path/to/kyuubi
export KYUUBI_HOST=your-kyuubi-host
export KYUUBI_PORT=10099

# 执行完整部署
./bin/knox-integration.sh all
```

或者分步执行：

```bash
# 1. 部署 Knox 配置
./bin/knox-integration.sh deploy

# 2. 配置 Kyuubi
./bin/knox-integration.sh configure

# 3. 启动服务
./bin/knox-integration.sh start

# 4. 测试集成
./bin/knox-integration.sh test
```

### 4. 访问验证

- **直接访问 Kyuubi**: `http://kyuubi-host:10099/ui/`
- **通过 Knox 访问**: `https://knox-host:8443/gateway/kyuubi/kyuubi/`

## 配置说明

### Kyuubi 配置

在 `conf/kyuubi-knox.conf` 中配置：

```properties
# 启用 Knox 集成
kyuubi.knox.integration.enabled=true

# Knox Gateway URL
kyuubi.knox.gateway.url=https://localhost:8443

# Knox 拓扑名称
kyuubi.knox.topology.name=kyuubi

# Knox 服务路径
kyuubi.knox.service.path=/kyuubi

# 启用 SSL
kyuubi.knox.ssl.enabled=true

# 启用认证
kyuubi.knox.authentication.enabled=true

# Knox 代理用户
kyuubi.knox.proxy.users=knox

# 启用 REST 协议
kyuubi.frontend.protocols=REST

# REST 服务配置
kyuubi.frontend.rest.bind.port=10099
kyuubi.frontend.bind.host=0.0.0.0

# 启用 CORS
kyuubi.frontend.rest.cors.enabled=true
kyuubi.frontend.rest.cors.allowed.origins=*
kyuubi.frontend.rest.cors.allowed.methods=GET,POST,PUT,DELETE,OPTIONS
kyuubi.frontend.rest.cors.allowed.headers=*
```

### Knox 配置

#### 拓扑配置 (`conf/topologies/kyuubi.xml`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<topology>
    <gateway>
        <provider>
            <role>authentication</role>
            <name>ShiroProvider</name>
            <enabled>true</enabled>
            <!-- 认证配置 -->
        </provider>
        <provider>
            <role>identity-assertion</role>
            <name>Default</name>
            <enabled>true</enabled>
        </provider>
        <provider>
            <role>authorization</role>
            <name>AclsAuthz</name>
            <enabled>true</enabled>
            <param>
                <name>kyuubi.acl</name>
                <value>*;*;*</value>
            </param>
        </provider>
    </gateway>
    
    <service>
        <role>KYUUBI</role>
        <url>http://kyuubi-host:10099</url>
    </service>
</topology>
```

#### 服务定义 (`conf/descriptors/kyuubi.json`)

```json
{
  "role": "KYUUBI",
  "name": "kyuubi",
  "version": "1.0.0",
  "params": {
    "kyuubi-site": {
      "kyuubi.frontend.rest.bind.port": "10099",
      "kyuubi.frontend.rest.web.ui.enabled": "true"
    }
  },
  "dispatch": {
    "keeper": {
      "default": "kyuubi-host:10099"
    }
  }
}
```

## 高级配置

### 1. SSL 配置

#### Knox SSL 配置

在 `conf/gateway-site.xml` 中配置：

```xml
<property>
    <name>gateway.port</name>
    <value>8443</value>
</property>
<property>
    <name>gateway.ssl.keystore</name>
    <value>/path/to/keystore.jks</value>
</property>
<property>
    <name>gateway.ssl.keystore.password</name>
    <value>password</value>
</property>
```

#### Kyuubi SSL 配置

```properties
# 启用 Kyuubi SSL
kyuubi.frontend.rest.ssl.enabled=true
kyuubi.frontend.rest.ssl.keystore=/path/to/kyuubi-keystore.jks
kyuubi.frontend.rest.ssl.keystore.password=password
```

### 2. 负载均衡配置

在 Knox 拓扑中配置多个 Kyuubi 实例：

```xml
<service>
    <role>KYUUBI</role>
    <url>http://kyuubi1:10099</url>
</service>
<service>
    <role>KYUUBI</role>
    <url>http://kyuubi2:10099</url>
</service>
```

### 3. 认证配置

#### LDAP 认证

```xml
<param>
    <name>main.ldapRealm.userDnTemplate</name>
    <value>uid={0},ou=people,dc=example,dc=com</value>
</param>
<param>
    <name>main.ldapRealm.contextFactory.url</name>
    <value>ldap://ldap-server:389</value>
</param>
```

#### Kerberos 认证

```properties
# Kyuubi Kerberos 配置
kyuubi.authentication=KERBEROS
kyuubi.authentication.kerberos.principal=kyuubi/_HOST@REALM
kyuubi.authentication.kerberos.keytab=/path/to/kyuubi.keytab
```

## 监控和日志

### 1. 健康检查

访问健康检查端点：

```bash
# Kyuubi 健康检查
curl http://kyuubi-host:10099/api/v1/info

# Knox 集成健康检查
curl http://kyuubi-host:10099/knox/health

# Knox Gateway 健康检查
curl -k https://knox-host:8443/gateway/admin/api/v1/version
```

### 2. 日志配置

在 `conf/log4j2.xml` 中配置：

```xml
<Logger name="org.apache.kyuubi.server.KnoxIntegrationService" level="DEBUG"/>
<Logger name="org.apache.knox" level="DEBUG"/>
```

### 3. 监控指标

Kyuubi 提供以下 Knox 相关的监控指标：

- `kyuubi.knox.integration.enabled`: Knox 集成是否启用
- `kyuubi.knox.health.check`: Knox 健康检查状态
- `kyuubi.knox.gateway.response.time`: Knox Gateway 响应时间

## 故障排除

### 1. 常见问题

#### 跨域问题

**症状**: 浏览器控制台显示 CORS 错误

**解决方案**:
```properties
# 确保 Kyuubi 启用了 CORS
kyuubi.frontend.rest.cors.enabled=true
kyuubi.frontend.rest.cors.allowed.origins=*
```

#### 认证问题

**症状**: 访问被拒绝或认证失败

**解决方案**:
1. 检查 Knox 认证配置
2. 验证用户权限设置
3. 检查 Kerberos 配置（如果使用）

#### 路由问题

**症状**: 无法通过 Knox 访问 Kyuubi

**解决方案**:
1. 确认 Knox 拓扑配置正确
2. 检查服务 URL 配置
3. 验证网络连通性

### 2. 调试方法

#### 启用调试日志

```properties
# 在 kyuubi-defaults.conf 中设置
kyuubi.logging.level=DEBUG
```

#### 网络调试

```bash
# 测试端口连通性
telnet kyuubi-host 10099
telnet knox-host 8443

# 测试 HTTP 请求
curl -v http://kyuubi-host:10099/api/v1/info
curl -k -v https://knox-host:8443/gateway/kyuubi/kyuubi/api/v1/info
```

## 性能优化

### 1. Knox 优化

```properties
# 调整线程池大小
gateway.thread.pool.size=200

# 配置连接池
gateway.connection.pool.size=100

# 启用压缩
gateway.compression.enabled=true
```

### 2. Kyuubi 优化

```properties
# 调整 JVM 参数
JAVA_OPTS="-Xmx4g -Xms2g"

# 配置会话池
kyuubi.session.engine.pool.size=10

# 优化查询引擎
kyuubi.engine.spark.sql.adaptive.enabled=true
```

## 安全考虑

### 1. 网络安全

- 使用 HTTPS 进行所有通信
- 配置防火墙规则限制访问
- 使用 VPN 或专用网络

### 2. 认证安全

- 使用强密码策略
- 定期轮换密钥和证书
- 监控异常访问模式

### 3. 数据安全

- 加密敏感配置数据
- 启用审计日志记录
- 定期备份配置和数据

## 版本兼容性

| Kyuubi 版本 | Knox 版本 | 状态 |
|-------------|-----------|------|
| 1.9.0+      | 1.6.0+    | ✅ 支持 |
| 1.8.x       | 1.5.x     | ⚠️ 部分支持 |
| 1.7.x       | 1.4.x     | ❌ 不支持 |

## 贡献指南

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 推送到分支
5. 创建 Pull Request

## 许可证

本项目遵循 Apache License 2.0 许可证。

## 支持

- 文档: [Kyuubi 官方文档](https://kyuubi.readthedocs.io/)
- 邮件列表: [Kyuubi 邮件列表](https://kyuubi.apache.org/mailing-lists.html)
- 问题报告: [GitHub Issues](https://github.com/apache/kyuubi/issues)