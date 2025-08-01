# 使用IntelliJ IDEA调试Knox-Kyuubi路径转发指南

## 🎯 调试目标

使用IntelliJ IDEA来调试Knox中对于Kyuubi路径转发的配置，主要包括：
1. **URL重写过程** - 分析请求URL如何被重写
2. **服务发现机制** - 验证Knox如何找到KYUUBIUI服务
3. **请求分发逻辑** - 跟踪请求如何被转发到Kyuubi
4. **响应处理流程** - 了解响应如何被处理和返回

## 🛠️ 环境准备

### 1. 获取Knox源码

```bash
# 克隆Knox源码仓库
git clone https://github.com/apache/knox.git
cd knox

# 切换到对应版本分支（建议使用你实际使用的版本）
git checkout rel/v1.6.1

# 或者直接下载源码包
wget https://archive.apache.org/dist/knox/1.6.1/knox-1.6.1-src.zip
unzip knox-1.6.1-src.zip
```

### 2. 在IDEA中导入项目

```bash
# 1. 打开IntelliJ IDEA
# 2. File -> Open -> 选择Knox源码目录
# 3. 选择"Import project from external model" -> Maven
# 4. 使用默认设置完成导入
```

### 3. 配置调试环境

#### 创建Knox调试配置

1. **配置运行配置**：
   - Run -> Edit Configurations
   - 点击 "+" -> Application
   - Name: `Knox Gateway Debug`
   - Main class: `org.apache.knox.gateway.launcher.Launcher`
   - Program arguments: (留空)
   - VM options: `-Dknox.gateway.home=/path/to/your/knox/installation`

2. **设置工作目录**：
   - Working directory: `/Users/junglelou/Downloads/knox-1.6.1.2`

3. **配置环境变量**：
   ```
   KNOX_HOME=/Users/junglelou/Downloads/knox-1.6.1.2
   JAVA_HOME=/Users/junglelou/local/jdk1.8.0_432.jdk/Contents/Home
   ```

## 🔍 关键断点设置

### 1. URL重写相关断点

#### UrlRewriteServletFilter.java
```java
// 文件位置: gateway-provider-rewrite/src/main/java/org/apache/knox/gateway/filter/rewrite/api/UrlRewriteServletFilter.java

public class UrlRewriteServletFilter implements Filter {
    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) 
            throws IOException, ServletException {
        
        // 在这里设置断点 - 观察请求进入重写过滤器
        HttpServletRequest httpRequest = (HttpServletRequest) request;
        String requestURI = httpRequest.getRequestURI();
        
        // 重要断点：观察URL重写前的原始请求
        UrlRewriteRequest rewriteRequest = new UrlRewriteRequestAdapter(httpRequest);
        
        // 重要断点：观察URL重写后的结果
        chain.doFilter(rewriteRequest, response);
    }
}
```

#### UrlRewriteProcessor.java
```java
// 文件位置: gateway-provider-rewrite/src/main/java/org/apache/knox/gateway/filter/rewrite/impl/UrlRewriteProcessor.java

public class UrlRewriteProcessor {
    public UrlRewriteStepStatus process(UrlRewriteContext context) throws Exception {
        
        // 断点1：观察重写规则的匹配过程
        String inputValue = context.getCurrentUrl();
        
        for (UrlRewriteStepProcessor step : steps) {
            // 断点2：观察每个重写步骤的执行
            UrlRewriteStepStatus stepStatus = step.process(context);
            
            if (stepStatus == UrlRewriteStepStatus.SUCCESS) {
                // 断点3：观察成功重写的URL
                String rewrittenUrl = context.getCurrentUrl();
                break;
            }
        }
        
        return status;
    }
}
```

### 2. 服务发现相关断点

#### DefaultTopologyService.java
```java
// 文件位置: gateway-server/src/main/java/org/apache/knox/gateway/services/topology/impl/DefaultTopologyService.java

public class DefaultTopologyService implements TopologyService {
    
    @Override
    public Collection<Topology> getTopologies() {
        // 断点：观察topology加载过程
        Map<File, Topology> map = topologies;
        return Collections.unmodifiableCollection(map.values());
    }
    
    private Topology loadTopology(File file) {
        // 断点：观察具体topology文件的解析
        Topology topology = null;
        try {
            topology = deploymentFactory.createTopology(file);
        } catch (Exception e) {
            // 断点：观察topology加载错误
            log.error("Failed to load topology from " + file.getAbsolutePath(), e);
        }
        return topology;
    }
}
```

#### ServiceDefinitionRegistry.java
```java
// 文件位置: gateway-server/src/main/java/org/apache/knox/gateway/service/definition/ServiceDefinitionRegistry.java

public class ServiceDefinitionRegistry {
    
    public ServiceDefinition getServiceDefinition(String role) {
        // 重要断点：观察KYUUBIUI服务定义的查找过程
        ServiceDefinition definition = services.get(role);
        
        if (definition == null) {
            // 断点：如果找不到服务定义，在这里观察
            log.warn("Service definition not found for role: " + role);
        }
        
        return definition;
    }
}
```

### 3. 请求分发相关断点

#### DefaultDispatch.java
```java
// 文件位置: gateway-provider-ha/src/main/java/org/apache/knox/gateway/dispatch/DefaultDispatch.java

public class DefaultDispatch extends AbstractGatewayDispatch {
    
    @Override
    protected void executeRequest(HttpUriRequest outboundRequest, 
                                 HttpServletRequest inboundRequest, 
                                 HttpServletResponse outboundResponse) throws IOException {
        
        // 重要断点：观察向后端服务发送的实际请求
        String targetUrl = outboundRequest.getURI().toString();
        
        try {
            // 断点：观察HTTP客户端的执行
            HttpResponse inboundResponse = client.execute(outboundRequest);
            
            // 断点：观察后端响应的处理
            writeOutboundResponse(inboundRequest, outboundResponse, inboundResponse);
            
        } catch (IOException e) {
            // 重要断点：观察连接错误的具体原因
            log.error("Error executing request to: " + targetUrl, e);
            throw e;
        }
    }
    
    protected HttpUriRequest createHttpRequest(String method, URI uri, 
                                              HttpServletRequest request) throws IOException {
        // 断点：观察创建的HTTP请求详情
        HttpUriRequest httpRequest = null;
        
        switch (method) {
            case "GET":
                httpRequest = new HttpGet(uri);
                break;
            // ... 其他HTTP方法
        }
        
        // 断点：观察请求头的复制过程
        copyRequestHeaders(request, httpRequest);
        
        return httpRequest;
    }
}
```

### 4. 配置加载相关断点

#### GatewayFilter.java
```java
// 文件位置: gateway-server/src/main/java/org/apache/knox/gateway/GatewayFilter.java

public class GatewayFilter implements Filter {
    
    @Override
    public void doFilter(ServletRequest servletRequest, ServletResponse servletResponse, 
                        FilterChain filterChain) throws IOException, ServletException {
        
        // 断点：观察请求进入网关的第一步
        HttpServletRequest request = (HttpServletRequest) servletRequest;
        String requestURI = request.getRequestURI();
        
        // 断点：观察topology匹配过程
        String topologyName = parseTopologyName(requestURI);
        Topology topology = topologies.getTopology(topologyName);
        
        if (topology == null) {
            // 断点：如果找不到topology
            response.sendError(HttpServletResponse.SC_NOT_FOUND);
            return;
        }
        
        // 断点：观察过滤器链的执行
        filterChain.doFilter(request, response);
    }
}
```

## 🎛️ 创建调试配置文件

### 1. 创建Knox调试启动配置

```bash
# 创建调试配置目录
mkdir -p ~/.idea_debug_knox

# 创建调试用的gateway-site.xml
cat > ~/.idea_debug_knox/gateway-site.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <!-- 启用详细日志 -->
    <property>
        <name>gateway.servlet.logging.enabled</name>
        <value>true</value>
    </property>
    
    <!-- 启用调试模式 -->
    <property>
        <name>gateway.debug.enabled</name>
        <value>true</value>
    </property>
    
    <!-- 设置详细的重写日志 -->
    <property>
        <name>gateway.rewrite.logging.enabled</name>
        <value>true</value>
    </property>
</configuration>
EOF
```

### 2. 创建IDEA运行配置模板

在IDEA中创建 `.idea/runConfigurations/Knox_Debug.xml`:

```xml
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Knox Debug" type="Application" factoryName="Application">
    <option name="MAIN_CLASS_NAME" value="org.apache.knox.gateway.launcher.Launcher" />
    <module name="gateway-server" />
    <option name="PROGRAM_PARAMETERS" value="" />
    <option name="VM_PARAMETERS" value="-Dknox.gateway.home=/Users/junglelou/Downloads/knox-1.6.1.2 -Dknox.gateway.conf.dir=/Users/junglelou/Downloads/knox-1.6.1.2/conf -Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=5005" />
    <option name="WORKING_DIRECTORY" value="/Users/junglelou/Downloads/knox-1.6.1.2" />
    <envs>
      <env name="KNOX_HOME" value="/Users/junglelou/Downloads/knox-1.6.1.2" />
      <env name="JAVA_HOME" value="/Users/junglelou/local/jdk1.8.0_432.jdk/Contents/Home" />
    </envs>
    <method v="2">
      <option name="Make" enabled="true" />
    </method>
  </configuration>
</component>
```

## 🔧 实际调试步骤

### 第一步：设置核心断点

```java
// 1. 在 UrlRewriteServletFilter.doFilter() 方法开始处设置断点
// 位置: gateway-provider-rewrite/src/main/java/org/apache/knox/gateway/filter/rewrite/api/UrlRewriteServletFilter.java:95

// 2. 在 DefaultDispatch.executeRequest() 方法中设置断点
// 位置: gateway-provider-ha/src/main/java/org/apache/knox/gateway/dispatch/DefaultDispatch.java:200

// 3. 在 ServiceDefinitionRegistry.getServiceDefinition() 方法中设置断点
// 位置: gateway-server/src/main/java/org/apache/knox/gateway/service/definition/ServiceDefinitionRegistry.java:85
```

### 第二步：启动调试会话

1. **启动Knox调试模式**：
   ```bash
   # 在IDEA中点击Debug按钮，或者
   # Run -> Debug 'Knox Debug'
   ```

2. **发送测试请求**：
   ```bash
   # 在另一个终端发送请求
   curl -k -v https://localhost:8443/gateway/emr/kyuubi/
   ```

### 第三步：分析调试信息

#### 在UrlRewriteServletFilter断点处观察：

```java
// 观察变量值
String requestURI = httpRequest.getRequestURI();  // 应该是 "/gateway/emr/kyuubi/"
String queryString = httpRequest.getQueryString();
String method = httpRequest.getMethod();

// 检查重写规则
UrlRewriteRulesDescriptor rules = processor.getRules();
```

#### 在DefaultDispatch断点处观察：

```java
// 观察目标URL
String targetUrl = outboundRequest.getURI().toString();  // 应该是 "http://localhost:10099/"

// 观察请求头
Header[] headers = outboundRequest.getAllHeaders();

// 观察HTTP客户端配置
HttpClient client = this.client;
```

#### 在ServiceDefinitionRegistry断点处观察：

```java
// 观察服务角色
String role = "KYUUBIUI";

// 观察服务定义
ServiceDefinition definition = services.get(role);

// 检查是否找到服务定义
if (definition != null) {
    String version = definition.getVersion();
    String name = definition.getName();
}
```

## 🧪 创建调试测试用例

### 1. 创建调试测试类

```java
// 创建文件: src/test/java/org/apache/knox/gateway/debug/KyuubiPathDebugTest.java

package org.apache.knox.gateway.debug;

import org.apache.knox.gateway.filter.rewrite.api.UrlRewriteEnvironment;
import org.apache.knox.gateway.filter.rewrite.api.UrlRewriteProcessor;
import org.apache.knox.gateway.filter.rewrite.api.UrlRewriteRulesDescriptor;
import org.apache.knox.gateway.filter.rewrite.impl.UrlRewriteContextImpl;
import org.apache.knox.gateway.filter.rewrite.impl.UrlRewriteProcessorImpl;
import org.junit.Test;

public class KyuubiPathDebugTest {
    
    @Test
    public void testKyuubiUrlRewrite() throws Exception {
        // 创建重写环境
        UrlRewriteEnvironment environment = new MockUrlRewriteEnvironment();
        
        // 加载Kyuubi重写规则
        UrlRewriteRulesDescriptor rules = loadKyuubiRewriteRules();
        
        // 创建重写处理器
        UrlRewriteProcessor processor = new UrlRewriteProcessorImpl();
        processor.initialize(environment, rules);
        
        // 测试URL重写
        UrlRewriteContextImpl context = new UrlRewriteContextImpl(
            environment, 
            null, 
            null, 
            "IN", 
            "/gateway/emr/kyuubi/"
        );
        
        // 执行重写并设置断点观察结果
        processor.process(context);
        
        // 验证重写结果
        String rewrittenUrl = context.getCurrentUrl();
        System.out.println("Original URL: /gateway/emr/kyuubi/");
        System.out.println("Rewritten URL: " + rewrittenUrl);
        
        // 应该重写为: http://localhost:10099/
        assert rewrittenUrl.equals("http://localhost:10099/");
    }
    
    private UrlRewriteRulesDescriptor loadKyuubiRewriteRules() {
        // 加载你的rewrite.xml文件
        // 返回解析后的规则描述符
    }
}
```

### 2. 创建服务发现测试

```java
// 创建文件: src/test/java/org/apache/knox/gateway/debug/KyuubiServiceDiscoveryTest.java

package org.apache.knox.gateway.debug;

import org.apache.knox.gateway.service.definition.ServiceDefinition;
import org.apache.knox.gateway.service.definition.ServiceDefinitionRegistry;
import org.apache.knox.gateway.topology.Service;
import org.apache.knox.gateway.topology.Topology;
import org.junit.Test;

public class KyuubiServiceDiscoveryTest {
    
    @Test
    public void testKyuubiServiceDiscovery() {
        // 创建服务定义注册表
        ServiceDefinitionRegistry registry = new ServiceDefinitionRegistry();
        
        // 设置断点观察服务定义加载
        registry.load();
        
        // 查找KYUUBIUI服务定义
        ServiceDefinition kyuubiDef = registry.getServiceDefinition("KYUUBIUI");
        
        if (kyuubiDef != null) {
            System.out.println("Found KYUUBIUI service definition:");
            System.out.println("Name: " + kyuubiDef.getName());
            System.out.println("Version: " + kyuubiDef.getVersion());
        } else {
            System.out.println("KYUUBIUI service definition not found!");
        }
        
        // 测试topology中的服务配置
        Topology topology = loadTestTopology();
        Service kyuubiService = findServiceByRole(topology, "KYUUBIUI");
        
        if (kyuubiService != null) {
            System.out.println("Found KYUUBIUI service in topology:");
            System.out.println("URL: " + kyuubiService.getUrl());
        }
    }
    
    private Topology loadTestTopology() {
        // 加载你的emr.xml topology文件
    }
    
    private Service findServiceByRole(Topology topology, String role) {
        // 在topology中查找指定角色的服务
    }
}
```

## 📊 调试信息收集脚本

### 创建IDEA调试信息收集器

```java
// 创建文件: src/test/java/org/apache/knox/gateway/debug/DebugInfoCollector.java

package org.apache.knox.gateway.debug;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.Date;

public class DebugInfoCollector {
    
    private static final String DEBUG_OUTPUT_FILE = "knox-kyuubi-debug-info.txt";
    
    public static void collectDebugInfo(String context, Object... objects) {
        try (FileWriter writer = new FileWriter(DEBUG_OUTPUT_FILE, true)) {
            writer.write("\n=== " + context + " - " + new Date() + " ===\n");
            
            for (Object obj : objects) {
                if (obj != null) {
                    writer.write(obj.toString() + "\n");
                } else {
                    writer.write("null\n");
                }
            }
            
            writer.write("\n");
            writer.flush();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
    
    // 在关键断点处调用此方法收集信息
    public static void logUrlRewrite(String originalUrl, String rewrittenUrl) {
        collectDebugInfo(
            "URL_REWRITE", 
            "Original: " + originalUrl,
            "Rewritten: " + rewrittenUrl
        );
    }
    
    public static void logServiceDiscovery(String role, Object serviceDefinition) {
        collectDebugInfo(
            "SERVICE_DISCOVERY",
            "Role: " + role,
            "Service Definition: " + serviceDefinition
        );
    }
    
    public static void logDispatch(String targetUrl, String method) {
        collectDebugInfo(
            "REQUEST_DISPATCH",
            "Target URL: " + targetUrl,
            "Method: " + method
        );
    }
}
```

## 🎯 调试检查清单

在IDEA调试过程中，按以下清单逐一验证：

### URL重写阶段
- [ ] 请求正确进入 `UrlRewriteServletFilter`
- [ ] 原始URL为 `/gateway/emr/kyuubi/`
- [ ] 找到了正确的重写规则
- [ ] 重写后的URL为 `http://localhost:10099/`
- [ ] 重写规则的模式匹配正确

### 服务发现阶段
- [ ] `ServiceDefinitionRegistry` 中包含 `KYUUBIUI` 定义
- [ ] 服务定义版本为 `1.9.0`
- [ ] topology文件正确加载
- [ ] topology中包含KYUUBIUI服务配置

### 请求分发阶段
- [ ] `DefaultDispatch` 创建了正确的HTTP请求
- [ ] 目标URL为 `http://localhost:10099/`
- [ ] HTTP客户端配置正确
- [ ] 请求头复制正确

### 错误处理阶段
- [ ] 没有出现 `Service connectivity error`
- [ ] 没有SSL握手错误
- [ ] 没有找不到服务的错误

## 🚀 实际操作建议

1. **从简单断点开始**：
   ```java
   // 首先在入口点设置断点
   GatewayFilter.doFilter() // 第一个断点
   UrlRewriteServletFilter.doFilter() // 第二个断点
   DefaultDispatch.executeRequest() // 第三个断点
   ```

2. **逐步深入**：
   ```java
   // 如果URL重写有问题，深入重写逻辑
   UrlRewriteProcessor.process()
   UrlRewriteRuleProcessorImpl.process()
   
   // 如果服务发现有问题，深入服务加载逻辑
   ServiceDefinitionRegistry.getServiceDefinition()
   DefaultTopologyService.getTopologies()
   ```

3. **使用条件断点**：
   ```java
   // 只在处理KYUUBIUI相关请求时停止
   // 条件：requestURI.contains("kyuubi")
   
   // 只在处理特定服务角色时停止
   // 条件：role.equals("KYUUBIUI")
   ```

4. **观察变量变化**：
   - 在Variables窗口中关注关键变量
   - 使用Evaluate Expression计算复杂表达式
   - 利用Watch功能监控特定变量

通过这种系统性的IDEA调试方法，你可以精确地定位Knox-Kyuubi路径转发配置中的任何问题！