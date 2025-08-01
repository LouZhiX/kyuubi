# Kyuubi WebUI 与 Apache Knox 集成指南

## 概述

本文档介绍如何将 Kyuubi 1.9 的 WebUI 集成到 Apache Knox 中，实现统一的 Web 访问入口和安全管理。

## 架构设计

### 集成架构
```
用户浏览器 -> Knox Gateway -> Kyuubi WebUI
                |
                +-> 认证授权
                +-> 路由转发
                +-> SSL终止
```

### 组件说明
- **Knox Gateway**: 提供统一的 Web 访问入口，处理认证、授权和路由
- **Kyuubi WebUI**: 提供 SQL 查询、会话管理、作业监控等功能
- **Kyuubi REST API**: 提供后端服务接口

## 配置步骤

### 1. Knox 配置

#### 1.1 安装 Knox
```bash
# 下载并安装 Knox
wget https://downloads.apache.org/knox/1.6.0/knox-1.6.0.tar.gz
tar -xzf knox-1.6.0.tar.gz
cd knox-1.6.0
```

#### 1.2 配置 Knox 拓扑
创建拓扑文件 `conf/topologies/kyuubi.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<topology>
    <gateway>
        <provider>
            <role>authentication</role>
            <name>ShiroProvider</name>
            <enabled>true</enabled>
            <param>
                <name>sessionTimeout</name>
                <value>30</value>
            </param>
            <param>
                <name>main.ldapRealm</name>
                <value>org.apache.hadoop.gateway.shirorealm.KnoxLdapRealm</value>
            </param>
            <param>
                <name>main.ldapRealm.userDnTemplate</name>
                <value>uid={0},ou=people,dc=hadoop,dc=apache,dc=org</value>
            </param>
            <param>
                <name>main.ldapRealm.contextFactory.url</name>
                <value>ldap://localhost:33389</value>
            </param>
            <param>
                <name>main.ldapRealm.contextFactory.authenticationMechanism</name>
                <value>simple</value>
            </param>
            <param>
                <name>urls./**</name>
                <value>authcBasic</value>
            </param>
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
        <url>http://localhost:10099</url>
    </service>
</topology>
```

#### 1.3 配置 Knox 服务定义
创建服务定义文件 `conf/descriptors/kyuubi.json`:

```json
{
  "role": "KYUUBI",
  "name": "kyuubi",
  "version": "1.0.0",
  "params": {
    "webhdfs-site": {
      "webhdfs.acl.permission.enabled": "true"
    }
  },
  "dispatch": {
    "keeper": {
      "default": "0.0.0.0:10099"
    }
  },
  "deployment": {
    "services": [
      {
        "name": "kyuubi",
        "params": {
          "webhdfs-site": {
            "webhdfs.acl.permission.enabled": "true"
          }
        }
      }
    ]
  }
}
```

### 2. Kyuubi 配置

#### 2.1 启用 REST 协议
在 `conf/kyuubi-defaults.conf` 中配置:

```properties
# 启用 REST 协议
kyuubi.frontend.protocols=REST

# REST 服务端口
kyuubi.frontend.rest.bind.port=10099

# 绑定地址
kyuubi.frontend.bind.host=0.0.0.0

# 启用 WebUI
kyuubi.frontend.rest.web.ui.enabled=true

# WebUI 静态资源路径
kyuubi.frontend.rest.web.ui.static.path=dist

# 允许跨域访问（用于 Knox 代理）
kyuubi.frontend.rest.cors.enabled=true
kyuubi.frontend.rest.cors.allowed.origins=*
kyuubi.frontend.rest.cors.allowed.methods=GET,POST,PUT,DELETE,OPTIONS
kyuubi.frontend.rest.cors.allowed.headers=*
```

#### 2.2 配置认证
```properties
# 启用认证
kyuubi.authentication=KERBEROS

# Kerberos 配置
kyuubi.authentication.kerberos.principal=kyuubi/_HOST@REALM
kyuubi.authentication.kerberos.keytab=/path/to/kyuubi.keytab

# 允许 Knox 代理用户
kyuubi.authentication.proxy.users=knox
```

### 3. 启动服务

#### 3.1 启动 Kyuubi
```bash
# 启动 Kyuubi 服务器
bin/kyuubi start
```

#### 3.2 启动 Knox
```bash
# 启动 Knox Gateway
bin/gateway.sh start
```

### 4. 访问验证

#### 4.1 通过 Knox 访问 Kyuubi WebUI
```
https://knox-host:8443/gateway/kyuubi/kyuubi/
```

#### 4.2 直接访问 Kyuubi WebUI
```
http://kyuubi-host:10099/ui/
```

## 高级配置

### 1. SSL 配置

#### 1.1 Knox SSL 配置
在 `conf/gateway-site.xml` 中配置:

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

#### 1.2 Kyuubi SSL 配置
```properties
# 启用 Kyuubi SSL
kyuubi.frontend.rest.ssl.enabled=true
kyuubi.frontend.rest.ssl.keystore=/path/to/kyuubi-keystore.jks
kyuubi.frontend.rest.ssl.keystore.password=password
```

### 2. 负载均衡配置

#### 2.1 多 Kyuubi 实例
在 Knox 拓扑中配置多个 Kyuubi 实例:

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

### 3. 监控和日志

#### 3.1 Knox 监控
```bash
# 查看 Knox 状态
bin/gateway.sh status

# 查看 Knox 日志
tail -f logs/gateway.log
```

#### 3.2 Kyuubi 监控
```bash
# 查看 Kyuubi 状态
bin/kyuubi status

# 查看 Kyuubi 日志
tail -f logs/kyuubi-server.log
```

## 故障排除

### 1. 常见问题

#### 1.1 跨域问题
- 确保 Kyuubi 启用了 CORS 支持
- 检查 Knox 的 CORS 配置

#### 1.2 认证问题
- 验证 Kerberos 配置
- 检查用户权限设置

#### 1.3 路由问题
- 确认 Knox 拓扑配置正确
- 检查服务 URL 配置

### 2. 调试方法

#### 2.1 启用调试日志
在 `conf/log4j2.xml` 中配置:

```xml
<Logger name="org.apache.kyuubi" level="DEBUG"/>
<Logger name="org.apache.knox" level="DEBUG"/>
```

#### 2.2 网络调试
```bash
# 测试端口连通性
telnet kyuubi-host 10099
telnet knox-host 8443

# 测试 HTTP 请求
curl -k https://knox-host:8443/gateway/kyuubi/kyuubi/api/v1/info
```

## 性能优化

### 1. Knox 优化
- 调整线程池大小
- 配置连接池
- 启用压缩

### 2. Kyuubi 优化
- 调整 JVM 参数
- 配置会话池
- 优化查询引擎

## 安全考虑

### 1. 网络安全
- 使用 HTTPS
- 配置防火墙规则
- 限制网络访问

### 2. 认证安全
- 使用强密码策略
- 定期轮换密钥
- 监控异常访问

### 3. 数据安全
- 加密敏感数据
- 审计日志记录
- 数据备份策略

## 总结

通过以上配置，可以实现 Kyuubi WebUI 与 Apache Knox 的完整集成，提供统一的 Web 访问入口和安全管理。这种集成方式具有以下优势：

1. **统一入口**: 通过 Knox 提供统一的 Web 访问入口
2. **安全管理**: 利用 Knox 的认证、授权和安全功能
3. **负载均衡**: 支持多 Kyuubi 实例的负载均衡
4. **SSL 终止**: 在 Knox 层处理 SSL，简化后端配置
5. **监控集成**: 统一的监控和日志管理

建议在生产环境中使用此集成方案，并根据实际需求进行相应的配置调整。