# Kyuubi API重写规则详细分析

## 🎯 问题分析

根据你提供的HTTP请求信息，Kyuubi WebUI包含多种类型的请求：

```
GET http://localhost:10099/api/v1/admin/sessions
Referer: http://localhost:10099/ui/management/session
```

这表明Kyuubi使用了以下URL模式：
- **WebUI页面**: `/ui/*`
- **API接口**: `/api/v1/*`
- **静态资源**: `/static/*`, `/assets/*`

## 🔧 完整的重写规则构建

### 当前问题分析

你的原始重写规则可能过于简单，只处理了根路径，但没有覆盖API和静态资源路径。

### 完整的rewrite.xml配置

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!--
   Complete Kyuubi rewrite rules for all URL patterns
-->
<rules>
    <!-- ============================================ -->
    <!--           入站重写规则 (IN Direction)        -->
    <!-- ============================================ -->
    
    <!-- 1. 根路径重写 -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/root" pattern="*://*:*/**/kyuubi">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/"/>
    </rule>
    
    <!-- 2. 主页面重写 -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/home" pattern="*://*:*/**/kyuubi/">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/"/>
    </rule>
    
    <!-- 3. UI页面重写 -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/ui" pattern="*://*:*/**/kyuubi/ui/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/ui/{**}"/>
    </rule>
    
    <!-- 4. API接口重写 (关键！) -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/api" pattern="*://*:*/**/kyuubi/api/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/api/{**}"/>
    </rule>
    
    <!-- 5. 静态资源重写 -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/assets" pattern="*://*:*/**/kyuubi/assets/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/assets/{**}"/>
    </rule>
    
    <!-- 6. 其他静态资源 -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/static" pattern="*://*:*/**/kyuubi/static/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/static/{**}"/>
    </rule>
    
    <!-- 7. 通用路径重写 (最后匹配) -->
    <rule dir="IN" name="KYUUBIUI/kyuubi/inbound/path" pattern="*://*:*/**/kyuubi/{**}">
        <rewrite template="{$serviceUrl[KYUUBIUI]}/{**}"/>
    </rule>

    <!-- ============================================ -->
    <!--           出站重写规则 (OUT Direction)       -->
    <!-- ============================================ -->
    
    <!-- 1. 重写响应头中的Location -->
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/location" pattern="Location: {scheme}://{host}:{port}/{**}">
        <rewrite template="Location: {$frontend[url]}/kyuubi/{**}"/>
    </rule>
    
    <!-- 2. 重写HTML中的绝对路径链接 -->
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/html/href" pattern="href=&quot;/{**}&quot;">
        <rewrite template="href=&quot;{$frontend[url]}/kyuubi/{**}&quot;"/>
    </rule>
    
    <!-- 3. 重写HTML中的script src -->
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/html/script" pattern="src=&quot;/{**}&quot;">
        <rewrite template="src=&quot;{$frontend[url]}/kyuubi/{**}&quot;"/>
    </rule>
    
    <!-- 4. 重写CSS中的url() -->
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/css/url" pattern="url\(/{**}\)">
        <rewrite template="url({$frontend[url]}/kyuubi/{**})"/>
    </rule>
    
    <!-- 5. 重写API响应中的URL (如果有) -->
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/api/url" pattern='"url":"/{**}"'>
        <rewrite template='"url":"{$frontend[url]}/kyuubi/{**}"'/>
    </rule>
    
    <!-- 6. 重写JavaScript中的API调用路径 -->
    <rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/js/api" pattern="['\"]/{api|ui}/{**}['\"]">
        <rewrite template>"{$frontend[url]}/kyuubi/{api|ui}/{**}"</rewrite>
    </rule>

</rules>
```

## 📊 URL映射分析表

| 客户端请求 | Knox入站重写后 | 说明 |
|------------|----------------|------|
| `https://knox:8443/gateway/emr/kyuubi/` | `http://localhost:10099/` | 主页 |
| `https://knox:8443/gateway/emr/kyuubi/ui/management/session` | `http://localhost:10099/ui/management/session` | UI页面 |
| `https://knox:8443/gateway/emr/kyuubi/api/v1/admin/sessions` | `http://localhost:10099/api/v1/admin/sessions` | API接口 |
| `https://knox:8443/gateway/emr/kyuubi/assets/index.js` | `http://localhost:10099/assets/index.js` | 静态资源 |

## 🔍 调试重写规则

### 1. 创建重写规则测试脚本

```bash
cat > test-rewrite-rules.sh << 'EOF'
#!/bin/bash

# Knox重写规则测试脚本

KNOX_URL="https://localhost:8443/gateway/emr/kyuubi"

echo "=== 测试Kyuubi重写规则 ==="

# 测试主页
echo "1. 测试主页访问:"
curl -k -s -o /dev/null -w "HTTP %{http_code} - %{url_effective}\n" "${KNOX_URL}/"

# 测试UI页面
echo "2. 测试UI页面:"
curl -k -s -o /dev/null -w "HTTP %{http_code} - %{url_effective}\n" "${KNOX_URL}/ui/management/session"

# 测试API接口
echo "3. 测试API接口:"
curl -k -s -o /dev/null -w "HTTP %{http_code} - %{url_effective}\n" "${KNOX_URL}/api/v1/admin/sessions"

# 测试静态资源
echo "4. 测试静态资源:"
curl -k -s -o /dev/null -w "HTTP %{http_code} - %{url_effective}\n" "${KNOX_URL}/assets/index.js"

echo "=== 测试完成 ==="
EOF

chmod +x test-rewrite-rules.sh
```

### 2. 启用重写调试日志

```bash
# 在Knox的log4j配置中添加
echo "log4j.logger.org.apache.knox.gateway.filter.rewrite=TRACE" >> \
  $KNOX_HOME/conf/gateway-log4j.properties

# 重启Knox
$KNOX_HOME/bin/gateway.sh restart
```

### 3. 实时监控重写过程

```bash
# 监控重写日志
tail -f $KNOX_HOME/logs/gateway.log | grep -E "(rewrite|KYUUBIUI)"
```

## 🛠️ 针对你的API请求的具体重写

### 问题请求分析

```
原始直接请求: http://localhost:10099/api/v1/admin/sessions
通过Knox应该是: https://localhost:8443/gateway/emr/kyuubi/api/v1/admin/sessions
```

### 确保API重写规则正确

```xml
<!-- 这条规则处理你的API请求 -->
<rule dir="IN" name="KYUUBIUI/kyuubi/inbound/api" pattern="*://*:*/**/kyuubi/api/{**}">
    <rewrite template="{$serviceUrl[KYUUBIUI]}/api/{**}"/>
</rule>
```

### 验证重写是否生效

```bash
# 测试你的具体API
curl -k -v https://localhost:8443/gateway/emr/kyuubi/api/v1/admin/sessions

# 观察Knox日志中的重写过程
tail -f $KNOX_HOME/logs/gateway.log | grep -A5 -B5 "api/v1/admin/sessions"
```

## ⚠️ 常见重写问题

### 问题1: API请求返回404

**原因**: 缺少API路径的重写规则
**解决**: 添加专门的API重写规则

```xml
<rule dir="IN" name="KYUUBIUI/kyuubi/inbound/api" pattern="*://*:*/**/kyuubi/api/{**}">
    <rewrite template="{$serviceUrl[KYUUBIUI]}/api/{**}"/>
</rule>
```

### 问题2: 静态资源加载失败

**原因**: 出站重写规则不完整
**解决**: 完善HTML/CSS/JS的出站重写

```xml
<rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/html/href" pattern="href=&quot;/{**}&quot;">
    <rewrite template="href=&quot;{$frontend[url]}/kyuubi/{**}&quot;"/>
</rule>
```

### 问题3: AJAX请求失败

**原因**: JavaScript中的API调用路径没有被重写
**解决**: 添加JavaScript API路径重写

```xml
<rule dir="OUT" name="KYUUBIUI/kyuubi/outbound/js/api" pattern="/api/">
    <rewrite template="{$frontend[url]}/kyuubi/api/"/>
</rule>
```

## 🎯 完整的解决方案

### 1. 更新你的rewrite.xml

```bash
# 备份现有配置
cp $KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml \
   $KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml.backup

# 使用完整的重写规则
cp kyuubi-complete-rewrite.xml $KNOX_HOME/data/services/kyuubiui/1.9.0/rewrite.xml
```

### 2. 重启Knox并测试

```bash
# 重启Knox
$KNOX_HOME/bin/gateway.sh restart

# 测试所有路径
./test-rewrite-rules.sh
```

### 3. 验证你的具体API

```bash
# 测试sessions API
curl -k -H "Accept: application/json" \
  https://localhost:8443/gateway/emr/kyuubi/api/v1/admin/sessions

# 预期结果: 应该返回与直接访问 http://localhost:10099/api/v1/admin/sessions 相同的内容
```

通过这个完整的重写规则配置，你的所有Kyuubi API请求都应该能够正确工作！