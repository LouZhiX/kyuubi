# Knox到Kyuubi的URL映射错误诊断指南

## 🔍 什么是URL映射错误？

URL映射错误是指Knox网关无法正确将客户端请求的URL转换为后端服务的实际URL，或者无法正确处理后端服务返回的响应中的URL。

## 📊 如何判断存在URL映射错误？

### 1. **日志错误模式识别**

#### 典型的映射错误日志特征：

```bash
# 错误模式1：服务连接错误
Service connectivity error.

# 错误模式2：URL重写失败
Failed to rewrite URL: https://localhost:8443/gateway/emr/kyuubi

# 错误模式3：未知服务错误
Unknown service: KYUUBIUI

# 错误模式4：路径不匹配
No route found for path: /gateway/emr/kyuubi

# 错误模式5：循环重定向
Circular redirect detected
```

#### 在你的案例中的具体表现：
```
javax.net.ssl.SSLHandshakeException: PKIX path building failed
```
这表明Knox试图以HTTPS方式连接到自己（localhost:8443），而不是连接到Kyuubi服务。

### 2. **URL流转过程诊断**

Knox的URL处理流程：
```
客户端请求 → Knox入站重写 → 后端服务请求 → 后端响应 → Knox出站重写 → 客户端响应
```

#### 正确的URL流转应该是：
```
https://knox:8443/gateway/emr/kyuubi/
                ↓ (入站重写)
http://localhost:10099/
                ↓ (Kyuubi响应)
http://localhost:10099/ui/overview
                ↓ (出站重写)
https://knox:8443/gateway/emr/kyuubi/ui/overview
```

#### 错误的URL流转（你遇到的问题）：
```
https://knox:8443/gateway/emr/kyuubi/
                ↓ (错误的重写)
https://localhost:8443/gateway/emr/kyuubi/  ❌ 循环调用自己
```

## 🛠️ 诊断方法和工具

### 方法1: 日志分析法

```bash
# 查看Knox gateway日志中的URL重写过程
grep -E "(rewrite|dispatch)" /path/to/knox/logs/gateway.log

# 查找特定的URL模式
grep -E "(localhost:8443|localhost:10099)" /path/to/knox/logs/gateway.log

# 查看最近的连接错误
tail -100 /path/to/knox/logs/gateway.log | grep -A5 -B5 "connectivity error"
```

### 方法2: 网络请求追踪法

```bash
# 使用curl追踪完整的请求过程
curl -v -k https://localhost:8443/gateway/emr/kyuubi/ 2>&1 | tee curl-trace.log

# 分析重定向链
curl -k -L -v https://localhost:8443/gateway/emr/kyuubi/ 2>&1 | grep -E "(Location|> GET|< HTTP)"
```

### 方法3: 配置文件检查法

```bash
# 检查topology配置中的URL
grep -A5 -B5 "KYUUBIUI" /path/to/knox/conf/topologies/emr.xml

# 检查服务定义是否存在
ls -la /path/to/knox/data/services/kyuubiui/

# 验证重写规则
cat /path/to/knox/data/services/kyuubiui/1.9.0/rewrite.xml
```

## 🔧 常见URL映射错误类型

### 错误类型1: 服务URL配置错误

**问题表现：**
```xml
<service>
    <role>KYUUBIUI</role>
    <!-- 错误：指向了Knox自己 -->
    <url>https://localhost:8443/gateway/emr/kyuubi</url>
</service>
```

**正确配置：**
```xml
<service>
    <role>KYUUBIUI</role>
    <!-- 正确：指向Kyuubi实际服务 -->
    <url>http://localhost:10099</url>
</service>
```

### 错误类型2: 重写规则缺失或错误

**问题：** 缺少rewrite.xml文件或规则不正确

**解决方案：** 创建正确的重写规则：
```xml
<rules>
    <!-- 入站规则：将Knox URL映射到Kyuubi URL -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/root" 
          pattern="*://*:*/**/kyuubi">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/"/>
    </rule>
    
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/path" 
          pattern="*://*:*/**/kyuubi/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/{**}"/>
    </rule>
</rules>
```

### 错误类型3: 服务定义缺失

**问题：** Knox找不到KYUUBIUI服务定义

**检查方法：**
```bash
# 检查服务定义目录是否存在
ls -la $KNOX_HOME/data/services/ | grep kyuubi

# 检查service.xml是否存在
ls -la $KNOX_HOME/data/services/kyuubiui/1.9.0/service.xml
```

### 错误类型4: 路径匹配问题

**问题：** URL路径模式不匹配

**检查服务路由配置：**
```xml
<routes>
    <route path="/kyuubi">           <!-- 精确匹配 -->
    <route path="/kyuubi/**">        <!-- 通配符匹配 -->
</routes>
```

## 🚨 你的具体问题诊断

基于你提供的错误信息，问题诊断：

### 1. 错误症状分析：
```
SSLHandshakeException: PKIX path building failed
Connection exception dispatching request: https://localhost:8443/gateway/emr/kyuubi
```

这说明Knox试图向 `https://localhost:8443/gateway/emr/kyuubi` 发送请求，这是**错误的**，因为：
- 这是Knox自己的地址，不是Kyuubi的地址
- 造成了循环调用

### 2. 根本原因：
1. **topology配置错误**：service URL可能指向了Knox自己
2. **服务定义缺失**：Knox不知道如何处理KYUUBIUI请求
3. **重写规则错误**：URL重写没有正确执行

### 3. 具体验证步骤：

```bash
# 步骤1：检查当前topology配置
cat /Users/junglelou/Downloads/knox-1.6.1.2/conf/topologies/emr.xml | grep -A5 KYUUBIUI

# 步骤2：检查服务定义是否存在
ls -la /Users/junglelou/Downloads/knox-1.6.1.2/data/services/kyuubiui/

# 步骤3：查看Knox尝试连接的实际URL
tail -20 /Users/junglelou/Downloads/knox-1.6.1.2/logs/gateway.log | grep -E "(dispatch|request)"
```

## 🎯 快速修复验证

### 修复后验证URL映射是否正确：

```bash
# 1. 启用Knox调试日志（可选）
echo "knox.gateway.log.level=DEBUG" >> $KNOX_HOME/conf/gateway-site.xml

# 2. 重启Knox
$KNOX_HOME/bin/gateway.sh restart

# 3. 发送测试请求并观察日志
curl -k https://localhost:8443/gateway/emr/kyuubi/ &
tail -f $KNOX_HOME/logs/gateway.log | grep -E "(rewrite|dispatch|KYUUBIUI)"

# 4. 验证正确的URL重写
# 正确的日志应该显示：
# - 入站URL: /gateway/emr/kyuubi
# - 重写后URL: http://localhost:10099/
# - 没有循环调用错误
```

## 📋 URL映射检查清单

使用此清单确保URL映射配置正确：

- [ ] topology中的service URL指向正确的Kyuubi地址 (`http://localhost:10099`)
- [ ] 服务定义目录存在 (`$KNOX_HOME/data/services/kyuubiui/1.9.0/`)
- [ ] service.xml文件存在且配置正确
- [ ] rewrite.xml文件存在且规则正确
- [ ] Knox日志中没有循环调用错误
- [ ] 可以通过curl直接访问Kyuubi (`http://localhost:10099`)
- [ ] Knox代理请求不会重定向到自己

通过这些方法，你可以准确判断和解决Knox到Kyuubi的URL映射错误问题。