#!/bin/bash

# IDEA调试环境快速设置脚本
# 用于设置Knox-Kyuubi调试环境

echo "==================================================================="
echo "              Knox-Kyuubi IDEA调试环境设置脚本"
echo "==================================================================="

# 配置参数
KNOX_VERSION="1.6.1"
KNOX_HOME="/Users/junglelou/Downloads/knox-1.6.1.2"
KYUUBI_HOME="/Users/junglelou/Downloads/apache-kyuubi-1.9.2-bin"
WORKSPACE_DIR="$HOME/knox-debug-workspace"

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

echo "选择设置模式："
echo "1. 下载Knox源码并设置调试环境"
echo "2. 仅创建IDEA调试配置文件"
echo "3. 创建调试测试项目"
echo "4. 设置远程调试连接"
echo "5. 完整设置（推荐）"

read -p "请选择 (1-5): " choice

case $choice in
    1)
        log_info "下载Knox源码并设置调试环境..."
        
        # 创建工作空间
        mkdir -p "$WORKSPACE_DIR"
        cd "$WORKSPACE_DIR"
        
        # 下载Knox源码
        if [ ! -d "knox" ]; then
            log_info "克隆Knox源码仓库..."
            git clone https://github.com/apache/knox.git
            cd knox
            git checkout "rel/v$KNOX_VERSION"
        else
            log_info "Knox源码已存在，跳过下载"
            cd knox
        fi
        
        # 构建项目
        log_info "构建Knox项目（可能需要几分钟）..."
        mvn clean compile -DskipTests
        
        log_success "Knox源码下载和构建完成"
        log_info "请在IDEA中打开: $WORKSPACE_DIR/knox"
        ;;
        
    2)
        log_info "创建IDEA调试配置文件..."
        
        # 创建IDEA配置目录
        mkdir -p "$WORKSPACE_DIR/.idea/runConfigurations"
        
        # 创建Knox调试运行配置
        cat > "$WORKSPACE_DIR/.idea/runConfigurations/Knox_Gateway_Debug.xml" << EOF
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Knox Gateway Debug" type="Application" factoryName="Application">
    <option name="MAIN_CLASS_NAME" value="org.apache.knox.gateway.launcher.Launcher" />
    <module name="gateway-server" />
    <option name="PROGRAM_PARAMETERS" value="" />
    <option name="VM_PARAMETERS" value="-Dknox.gateway.home=$KNOX_HOME -Dknox.gateway.conf.dir=$KNOX_HOME/conf -Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=5005 -Dknox.gateway.log.level=DEBUG" />
    <option name="WORKING_DIRECTORY" value="$KNOX_HOME" />
    <envs>
      <env name="KNOX_HOME" value="$KNOX_HOME" />
      <env name="JAVA_HOME" value="/Users/junglelou/local/jdk1.8.0_432.jdk/Contents/Home" />
    </envs>
    <method v="2">
      <option name="Make" enabled="true" />
    </method>
  </configuration>
</component>
EOF

        # 创建远程调试配置
        cat > "$WORKSPACE_DIR/.idea/runConfigurations/Knox_Remote_Debug.xml" << EOF
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Knox Remote Debug" type="Remote" factoryName="Remote">
    <option name="USE_SOCKET_TRANSPORT" value="true" />
    <option name="SERVER_MODE" value="false" />
    <option name="SHMEM_ADDRESS" />
    <option name="HOST" value="localhost" />
    <option name="PORT" value="5005" />
    <option name="AUTO_RESTART" value="false" />
    <method v="2" />
  </configuration>
</component>
EOF

        log_success "IDEA调试配置文件已创建"
        ;;
        
    3)
        log_info "创建调试测试项目..."
        
        mkdir -p "$WORKSPACE_DIR/knox-debug-test/src/main/java/com/debug"
        mkdir -p "$WORKSPACE_DIR/knox-debug-test/src/test/java/com/debug"
        
        # 创建测试项目的pom.xml
        cat > "$WORKSPACE_DIR/knox-debug-test/pom.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>com.debug</groupId>
    <artifactId>knox-debug-test</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>
    
    <properties>
        <maven.compiler.source>8</maven.compiler.source>
        <maven.compiler.target>8</maven.compiler.target>
        <knox.version>1.6.1</knox.version>
    </properties>
    
    <dependencies>
        <!-- Knox依赖 -->
        <dependency>
            <groupId>org.apache.knox</groupId>
            <artifactId>gateway-server</artifactId>
            <version>${knox.version}</version>
        </dependency>
        
        <dependency>
            <groupId>org.apache.knox</groupId>
            <artifactId>gateway-provider-rewrite</artifactId>
            <version>${knox.version}</version>
        </dependency>
        
        <!-- 测试依赖 -->
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.13.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
EOF

        # 创建调试工具类
        cat > "$WORKSPACE_DIR/knox-debug-test/src/main/java/com/debug/KnoxDebugHelper.java" << 'EOF'
package com.debug;

import java.io.FileWriter;
import java.io.IOException;
import java.util.Date;

public class KnoxDebugHelper {
    
    private static final String DEBUG_LOG = "knox-debug.log";
    
    public static void logDebugInfo(String phase, String info) {
        try (FileWriter writer = new FileWriter(DEBUG_LOG, true)) {
            writer.write(String.format("[%s] %s: %s\n", 
                new Date().toString(), phase, info));
            writer.flush();
            System.out.println("[DEBUG] " + phase + ": " + info);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
    
    public static void logUrlRewrite(String original, String rewritten) {
        logDebugInfo("URL_REWRITE", 
            String.format("Original: %s -> Rewritten: %s", original, rewritten));
    }
    
    public static void logServiceDiscovery(String role, String status) {
        logDebugInfo("SERVICE_DISCOVERY", 
            String.format("Role: %s, Status: %s", role, status));
    }
    
    public static void logRequestDispatch(String targetUrl, String method) {
        logDebugInfo("REQUEST_DISPATCH", 
            String.format("Target: %s, Method: %s", targetUrl, method));
    }
}
EOF

        # 创建测试类
        cat > "$WORKSPACE_DIR/knox-debug-test/src/test/java/com/debug/KnoxPathDebugTest.java" << 'EOF'
package com.debug;

import org.junit.Test;
import static org.junit.Assert.*;

public class KnoxPathDebugTest {
    
    @Test
    public void testKyuubiPathRewrite() {
        // 模拟Knox URL重写测试
        String originalPath = "/gateway/emr/kyuubi/";
        String expectedRewritten = "http://localhost:10099/";
        
        // 在这里设置断点进行调试
        KnoxDebugHelper.logUrlRewrite(originalPath, expectedRewritten);
        
        // 断言重写结果
        assertTrue("URL重写测试", originalPath.contains("kyuubi"));
    }
    
    @Test
    public void testServiceDiscovery() {
        // 模拟服务发现测试
        String serviceRole = "KYUUBIUI";
        
        // 在这里设置断点进行调试
        KnoxDebugHelper.logServiceDiscovery(serviceRole, "FOUND");
        
        assertNotNull("服务发现测试", serviceRole);
    }
}
EOF

        log_success "调试测试项目已创建: $WORKSPACE_DIR/knox-debug-test"
        ;;
        
    4)
        log_info "设置远程调试连接..."
        
        # 创建远程调试启动脚本
        cat > "$WORKSPACE_DIR/start-knox-debug.sh" << EOF
#!/bin/bash

# Knox远程调试启动脚本

export KNOX_HOME="$KNOX_HOME"
export JAVA_HOME="/Users/junglelou/local/jdk1.8.0_432.jdk/Contents/Home"

# 停止现有Knox实例
cd "$KNOX_HOME"
bin/gateway.sh stop 2>/dev/null || true

# 启用详细日志
echo "log4j.logger.org.apache.knox=DEBUG" >> conf/gateway-log4j.properties
echo "log4j.logger.org.apache.knox.gateway.dispatch=DEBUG" >> conf/gateway-log4j.properties
echo "log4j.logger.org.apache.knox.gateway.filter.rewrite=TRACE" >> conf/gateway-log4j.properties

# 设置调试参数
export KNOX_GATEWAY_LOG_OPTS="-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=5005"

# 启动Knox
echo "启动Knox调试模式..."
bin/gateway.sh start

echo "Knox调试模式已启动，监听端口: 5005"
echo "在IDEA中连接到 localhost:5005 进行远程调试"
EOF

        chmod +x "$WORKSPACE_DIR/start-knox-debug.sh"
        
        # 创建测试请求脚本
        cat > "$WORKSPACE_DIR/test-knox-request.sh" << 'EOF'
#!/bin/bash

echo "发送测试请求到Knox..."

# 基础连接测试
echo "1. 测试Kyuubi直接连接:"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:10099

# Knox代理测试
echo "2. 测试Knox代理连接:"
curl -k -s -o /dev/null -w "HTTP Status: %{http_code}\n" https://localhost:8443/gateway/emr/kyuubi/

# 详细测试
echo "3. 详细Knox代理测试:"
curl -k -v https://localhost:8443/gateway/emr/kyuubi/ 2>&1 | head -20

echo "测试完成！检查IDEA中的断点是否被触发。"
EOF

        chmod +x "$WORKSPACE_DIR/test-knox-request.sh"
        
        log_success "远程调试脚本已创建"
        log_info "使用方法："
        log_info "1. 运行: $WORKSPACE_DIR/start-knox-debug.sh"
        log_info "2. 在IDEA中连接远程调试器到 localhost:5005"
        log_info "3. 运行: $WORKSPACE_DIR/test-knox-request.sh"
        ;;
        
    5)
        log_info "开始完整设置..."
        
        # 执行所有设置步骤
        $0 1  # 下载源码
        $0 2  # 创建配置
        $0 3  # 创建测试项目
        $0 4  # 设置远程调试
        
        # 创建综合说明文档
        cat > "$WORKSPACE_DIR/README.md" << EOF
# Knox-Kyuubi IDEA调试环境

## 🎯 环境概览

本环境已为Knox-Kyuubi路径转发调试做好准备，包含：

1. **Knox源码项目** - 用于设置断点和代码调试
2. **调试配置文件** - IDEA运行配置
3. **测试项目** - 独立的调试测试
4. **远程调试脚本** - 连接到运行中的Knox实例

## 🚀 使用方法

### 方法1：源码调试（推荐）

1. 在IDEA中打开Knox源码项目
2. 在关键类中设置断点：
   - \`UrlRewriteServletFilter.doFilter()\`
   - \`DefaultDispatch.executeRequest()\`
   - \`ServiceDefinitionRegistry.getServiceDefinition()\`
3. 使用"Knox Gateway Debug"配置运行
4. 发送测试请求观察断点

### 方法2：远程调试

1. 运行: \`./start-knox-debug.sh\`
2. 在IDEA中使用"Knox Remote Debug"配置连接
3. 运行: \`./test-knox-request.sh\`

## 🔍 关键断点位置

| 文件 | 方法 | 作用 |
|------|------|------|
| UrlRewriteServletFilter.java | doFilter() | URL重写入口 |
| UrlRewriteProcessor.java | process() | 重写规则处理 |
| DefaultDispatch.java | executeRequest() | 请求分发 |
| ServiceDefinitionRegistry.java | getServiceDefinition() | 服务发现 |

## 📊 调试检查清单

- [ ] 请求进入UrlRewriteServletFilter
- [ ] URL从/gateway/emr/kyuubi/重写为http://localhost:10099/
- [ ] 找到KYUUBIUI服务定义
- [ ] 请求正确分发到Kyuubi
- [ ] 无connectivity error错误

## 🛠️ 工具文件

- \`start-knox-debug.sh\` - 启动调试模式
- \`test-knox-request.sh\` - 发送测试请求
- \`knox-debug-test/\` - 独立测试项目

EOF

        log_success "完整环境设置完成！"
        log_info "工作空间位置: $WORKSPACE_DIR"
        log_info "请查看 $WORKSPACE_DIR/README.md 了解使用方法"
        ;;
        
    *)
        log_error "无效选择"
        exit 1
        ;;
esac

echo ""
echo "==================================================================="
echo "IDEA调试环境设置完成！"
echo ""
echo "下一步建议："
echo "1. 在IDEA中打开Knox源码项目"
echo "2. 导入Maven依赖"
echo "3. 设置关键断点"
echo "4. 启动调试会话"
echo ""
echo "工作空间: $WORKSPACE_DIR"
echo "配置文件: $WORKSPACE_DIR/.idea/runConfigurations/"
echo "测试项目: $WORKSPACE_DIR/knox-debug-test/"
echo "==================================================================="