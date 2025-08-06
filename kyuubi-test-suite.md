# Kyuubi 1.9.2 版本综合测试用例集

## 概述
本测试套件专为Apache Kyuubi 1.9.2版本设计，包含15个核心测试用例，涵盖服务管理、SQL执行、多引擎支持、高可用性、安全认证、性能监控等关键功能模块。

## 环境准备
```bash
# 设置环境变量
export KYUUBI_HOME=/path/to/kyuubi-1.9.2
export SPARK_HOME=/path/to/spark
export JAVA_HOME=/path/to/java8+
export KYUUBI_CONF_DIR=$KYUUBI_HOME/conf
```

---

## 测试用例 1: Kyuubi服务基本启动与停止测试

### 目的
验证Kyuubi服务的基本启动、状态检查和停止功能

### 执行指令
```bash
# 1. 启动Kyuubi服务
$KYUUBI_HOME/bin/kyuubi start

# 2. 检查服务状态
$KYUUBI_HOME/bin/kyuubi status

# 3. 停止服务
$KYUUBI_HOME/bin/kyuubi stop
```

### 预期输入
- 正确配置的kyuubi-defaults.conf
- 可用的Spark环境

### 预期输出
```
启动输出:
Starting Kyuubi Server
Kyuubi server started, pid: 12345

状态检查输出:
Kyuubi server is running (pid: 12345)

停止输出:
Stopping Kyuubi server
Kyuubi server stopped
```

---

## 测试用例 2: Thrift JDBC连接测试

### 目的
验证通过JDBC连接Kyuubi服务的基本功能

### 执行指令
```bash
# 使用Beeline连接Kyuubi
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n testuser
```

### 预期输入
- 运行中的Kyuubi服务（端口10009）
- 有效的用户名

### 预期输出
```
Connecting to jdbc:hive2://localhost:10009
Connected to: Kyuubi (version 1.9.2)
Driver: Hive JDBC (version 2.3.9)
Transaction isolation: TRANSACTION_REPEATABLE_READ
Beeline version 2.3.9 by Apache Hive
0: jdbc:hive2://localhost:10009>
```

---

## 测试用例 3: 基本SQL查询执行测试

### 目的
验证通过Kyuubi执行基本SQL查询的功能

### 执行指令
```sql
-- 在Beeline中执行以下SQL
SHOW DATABASES;
CREATE DATABASE IF NOT EXISTS test_db;
USE test_db;
CREATE TABLE test_table (id INT, name STRING) USING PARQUET;
INSERT INTO test_table VALUES (1, 'Alice'), (2, 'Bob');
SELECT * FROM test_table;
```

### 预期输入
- 活跃的Beeline连接
- Spark SQL兼容的查询语句

### 预期输出
```
+----------+
|databaseName|
+----------+
|  default   |
|  test_db   |
+----------+

+----+-------+
| id | name  |
+----+-------+
| 1  | Alice |
| 2  | Bob   |
+----+-------+
2 rows selected (1.234 seconds)
```

---

## 测试用例 4: 多用户并发连接测试

### 目的
验证Kyuubi支持多用户同时连接和执行查询

### 执行指令
```bash
# 终端1 - 用户1连接
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n user1 &

# 终端2 - 用户2连接
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n user2 &

# 终端3 - 用户3连接
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n user3 &
```

### 预期输入
- 多个不同的用户名
- 足够的系统资源

### 预期输出
```
每个连接都应成功建立:
Connected to: Kyuubi (version 1.9.2)
各用户可独立执行SQL查询
```

---

## 测试用例 5: Spark引擎配置测试

### 目的
验证Kyuubi动态配置Spark引擎参数的功能

### 执行指令
```sql
-- 设置Spark配置
SET spark.sql.adaptive.enabled=true;
SET spark.sql.adaptive.coalescePartitions.enabled=true;
SET spark.executor.memory=2g;
SET spark.executor.cores=2;

-- 查看当前配置
SET spark.sql.adaptive.enabled;
SET spark.executor.memory;

-- 执行查询验证配置生效
SELECT /*+ REPARTITION(4) */ COUNT(*) FROM test_table;
```

### 预期输入
- 有效的Spark配置参数
- 足够的集群资源

### 预期输出
```
spark.sql.adaptive.enabled=true
spark.executor.memory=2g

查询结果显示配置已生效
+--------+
|count(1)|
+--------+
|   2    |
+--------+
```

---

## 测试用例 6: 引擎池管理测试

### 目的
验证Kyuubi的引擎池管理功能

### 执行指令
```bash
# 使用kyuubi-ctl管理引擎
$KYUUBI_HOME/bin/kyuubi-ctl list engine

# 删除指定引擎
$KYUUBI_HOME/bin/kyuubi-ctl delete engine --engine-id <engine-id>

# 查看引擎详情
$KYUUBI_HOME/bin/kyuubi-ctl get engine --engine-id <engine-id>
```

### 预期输入
- 运行中的Kyuubi服务
- 活跃的引擎实例

### 预期输出
```
引擎列表:
Engine ID: engine-123456
Engine Type: SPARK_SQL
User: testuser
Status: RUNNING
Created: 2024-01-01 10:00:00

删除成功:
Engine engine-123456 deleted successfully
```

---

## 测试用例 7: REST API接口测试

### 目的
验证Kyuubi REST API的基本功能

### 执行指令
```bash
# 获取服务器信息
curl -X GET "http://localhost:10099/api/v1/server/info"

# 获取会话列表
curl -X GET "http://localhost:10099/api/v1/sessions"

# 创建新会话
curl -X POST "http://localhost:10099/api/v1/sessions" \
  -H "Content-Type: application/json" \
  -d '{"user": "testuser", "engine": "SPARK_SQL"}'
```

### 预期输入
- 启用REST API的Kyuubi服务（端口10099）
- 有效的HTTP请求

### 预期输出
```json
{
  "version": "1.9.2",
  "gitCommit": "abc123",
  "buildDate": "2024-01-01",
  "branch": "branch-1.9"
}

{
  "sessions": [
    {
      "identifier": "session-123",
      "user": "testuser",
      "state": "RUNNING"
    }
  ]
}
```

---

## 测试用例 8: ZooKeeper高可用配置测试

### 目的
验证Kyuubi与ZooKeeper集成的高可用功能

### 执行指令
```bash
# 修改配置启用ZooKeeper HA
echo "kyuubi.ha.addresses=zk1:2181,zk2:2181,zk3:2181" >> $KYUUBI_CONF_DIR/kyuubi-defaults.conf
echo "kyuubi.ha.namespace=kyuubi-ha-test" >> $KYUUBI_CONF_DIR/kyuubi-defaults.conf

# 启动多个Kyuubi实例
$KYUUBI_HOME/bin/kyuubi start --conf kyuubi.frontend.thrift.binary.bind.port=10009
$KYUUBI_HOME/bin/kyuubi start --conf kyuubi.frontend.thrift.binary.bind.port=10010

# 使用ZooKeeper CLI检查注册信息
$KYUUBI_HOME/bin/kyuubi-zk-cli ls /kyuubi-ha-test
```

### 预期输入
- 运行中的ZooKeeper集群
- 正确的HA配置参数

### 预期输出
```
ZooKeeper节点信息:
[kyuubi-server-host1-10009, kyuubi-server-host2-10010]

客户端可以连接到任一实例:
Connected to: Kyuubi (version 1.9.2)
```

---

## 测试用例 9: 用户认证测试

### 目的
验证Kyuubi的用户认证机制

### 执行指令
```bash
# 配置LDAP认证
echo "kyuubi.authentication=LDAP" >> $KYUUBI_CONF_DIR/kyuubi-defaults.conf
echo "kyuubi.authentication.ldap.url=ldap://localhost:389" >> $KYUUBI_CONF_DIR/kyuubi-defaults.conf

# 重启服务
$KYUUBI_HOME/bin/kyuubi restart

# 使用LDAP用户连接
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n ldapuser -p password
```

### 预期输入
- 配置的LDAP服务器
- 有效的LDAP用户凭据

### 预期输出
```
认证成功:
Connected to: Kyuubi (version 1.9.2)

认证失败:
Error: Could not open client transport with JDBC Uri: 
jdbc:hive2://localhost:10009: Invalid username or password
```

---

## 测试用例 10: Flink引擎支持测试

### 目的
验证Kyuubi对Apache Flink引擎的支持

### 执行指令
```bash
# 配置Flink引擎
echo "kyuubi.engine.type=FLINK_SQL" >> $KYUUBI_CONF_DIR/kyuubi-defaults.conf
echo "kyuubi.engine.flink.application.jars=/path/to/flink-sql-client.jar" >> $KYUUBI_CONF_DIR/kyuubi-defaults.conf

# 重启Kyuubi
$KYUUBI_HOME/bin/kyuubi restart

# 连接并执行Flink SQL
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n flinkuser
```

### SQL测试
```sql
-- Flink SQL示例
CREATE TABLE source_table (
  id INT,
  name STRING,
  ts TIMESTAMP(3)
) WITH (
  'connector' = 'datagen'
);

SELECT * FROM source_table LIMIT 5;
```

### 预期输入
- 安装的Flink环境
- Flink SQL连接器

### 预期输出
```
+----+--------+-------------------------+
| id | name   | ts                      |
+----+--------+-------------------------+
| 1  | Alice  | 2024-01-01 10:00:00.000 |
| 2  | Bob    | 2024-01-01 10:00:01.000 |
+----+--------+-------------------------+
```

---

## 测试用例 11: 性能监控和指标测试

### 目的
验证Kyuubi的性能监控和指标收集功能

### 执行指令
```bash
# 启用指标收集
echo "kyuubi.metrics.enabled=true" >> $KYUUBI_CONF_DIR/kyuubi-defaults.conf
echo "kyuubi.metrics.reporters=JSON" >> $KYUUBI_CONF_DIR/kyuubi-defaults.conf

# 重启服务
$KYUUBI_HOME/bin/kyuubi restart

# 查看指标
curl -X GET "http://localhost:10099/api/v1/admin/metrics"

# 执行一些查询后再次查看指标
curl -X GET "http://localhost:10099/api/v1/admin/metrics" | jq '.gauges'
```

### 预期输入
- 启用指标的Kyuubi配置
- 一些SQL查询活动

### 预期输出
```json
{
  "version": "4.0.0",
  "gauges": {
    "kyuubi.connection.opened": {"value": 5},
    "kyuubi.connection.total": {"value": 10},
    "kyuubi.engine.spark.total": {"value": 3}
  },
  "counters": {
    "kyuubi.statement.opened": {"count": 15},
    "kyuubi.statement.closed": {"count": 12}
  }
}
```

---

## 测试用例 12: 大数据集查询性能测试

### 目的
验证Kyuubi处理大数据集查询的性能

### 执行指令
```sql
-- 创建大数据表
CREATE TABLE large_table (
  id BIGINT,
  value DOUBLE,
  category STRING,
  timestamp TIMESTAMP
) USING PARQUET
PARTITIONED BY (category);

-- 插入大量数据
INSERT INTO large_table
SELECT 
  monotonically_increasing_id() as id,
  rand() * 1000 as value,
  CASE WHEN rand() < 0.3 THEN 'A'
       WHEN rand() < 0.6 THEN 'B'
       ELSE 'C' END as category,
  current_timestamp() as timestamp
FROM range(1000000);

-- 执行复杂聚合查询
SELECT 
  category,
  COUNT(*) as count,
  AVG(value) as avg_value,
  MAX(value) as max_value
FROM large_table
GROUP BY category
ORDER BY count DESC;
```

### 预期输入
- 充足的存储空间
- 足够的内存和CPU资源

### 预期输出
```
+--------+--------+------------------+------------------+
|category|  count |         avg_value|         max_value|
+--------+--------+------------------+------------------+
|   B    | 300234 | 499.8234567      | 999.9876543      |
|   A    | 299876 | 500.1234567      | 999.8765432      |
|   C    | 399890 | 499.5678901      | 999.9999999      |
+--------+--------+------------------+------------------+
3 rows selected (15.234 seconds)
```

---

## 测试用例 13: 故障恢复测试

### 目的
验证Kyuubi的故障恢复和容错能力

### 执行指令
```bash
# 1. 启动Kyuubi并建立连接
$KYUUBI_HOME/bin/kyuubi start
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n testuser

# 2. 在另一个终端模拟故障
kill -9 $(cat $KYUUBI_HOME/pid/kyuubi-server.pid)

# 3. 重启服务
$KYUUBI_HOME/bin/kyuubi start

# 4. 重新连接并验证数据完整性
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n testuser
```

### SQL验证
```sql
-- 验证之前创建的表仍然存在
SHOW TABLES;
SELECT COUNT(*) FROM test_table;
```

### 预期输入
- 持久化存储的元数据
- 正确的故障恢复配置

### 预期输出
```
服务重启成功:
Starting Kyuubi Server
Kyuubi server started, pid: 54321

数据完整性验证:
+----------+
|tableName |
+----------+
|test_table|
+----------+

+--------+
|count(1)|
+--------+
|   2    |
+--------+
```

---

## 测试用例 14: 资源隔离测试

### 目的
验证Kyuubi的多租户资源隔离功能

### 执行指令
```bash
# 配置资源池
echo "kyuubi.engine.share.level=USER" >> $KYUUBI_CONF_DIR/kyuubi-defaults.conf
echo "spark.sql.adaptive.enabled=true" >> $KYUUBI_CONF_DIR/kyuubi-defaults.conf

# 用户1连接 - 分配较少资源
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n user1
```

### SQL配置
```sql
-- 用户1设置较小的资源
SET spark.executor.memory=1g;
SET spark.executor.cores=1;
SET spark.dynamicAllocation.maxExecutors=2;
```

```bash
# 用户2连接 - 分配较多资源
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n user2
```

### SQL配置
```sql
-- 用户2设置较大的资源
SET spark.executor.memory=4g;
SET spark.executor.cores=4;
SET spark.dynamicAllocation.maxExecutors=8;
```

### 预期输入
- 多用户环境
- 不同的资源配置

### 预期输出
```
用户1查询较慢:
2 rows selected (8.234 seconds)

用户2查询较快:
2 rows selected (3.456 seconds)

资源使用相互隔离，不会互相影响
```

---

## 测试用例 15: 数据湖集成测试

### 目的
验证Kyuubi与数据湖(Delta Lake/Iceberg)的集成

### 执行指令
```sql
-- Delta Lake测试
CREATE TABLE delta_table (
  id BIGINT,
  name STRING,
  age INT,
  updated_at TIMESTAMP
) USING DELTA
LOCATION '/tmp/delta-table';

-- 插入数据
INSERT INTO delta_table VALUES 
  (1, 'Alice', 25, current_timestamp()),
  (2, 'Bob', 30, current_timestamp());

-- 更新数据
UPDATE delta_table SET age = 26 WHERE name = 'Alice';

-- 查看历史版本
DESCRIBE HISTORY delta_table;

-- 时间旅行查询
SELECT * FROM delta_table VERSION AS OF 0;
```

### 预期输入
- 安装的Delta Lake或Iceberg依赖
- 配置的数据湖存储

### 预期输出
```
+-------+-----+---+-------------------------+
| id    |name |age| updated_at              |
+-------+-----+---+-------------------------+
| 1     |Alice| 26| 2024-01-01 10:00:00.000 |
| 2     | Bob | 30| 2024-01-01 10:00:00.000 |
+-------+-----+---+-------------------------+

历史版本:
+-------+-------------------+------+--------+
|version|timestamp          |userId|operation|
+-------+-------------------+------+--------+
| 0     |2024-01-01 10:00:00|user  |CREATE   |
| 1     |2024-01-01 10:01:00|user  |WRITE    |
| 2     |2024-01-01 10:02:00|user  |UPDATE   |
+-------+-------------------+------+--------+
```

---

## 测试执行脚本

### 自动化测试脚本
```bash
#!/bin/bash
# kyuubi-test-runner.sh

KYUUBI_HOME=${KYUUBI_HOME:-/path/to/kyuubi}
TEST_USER=${TEST_USER:-testuser}
TEST_DB=${TEST_DB:-kyuubi_test_db}

echo "开始执行Kyuubi 1.9.2综合测试..."

# 测试1: 服务启动
echo "测试1: 服务启动测试"
$KYUUBI_HOME/bin/kyuubi start
sleep 10
$KYUUBI_HOME/bin/kyuubi status

# 测试2-3: 基本SQL功能
echo "测试2-3: 基本SQL功能测试"
$KYUUBI_HOME/bin/beeline -u "jdbc:hive2://localhost:10009" -n $TEST_USER -e "
SHOW DATABASES;
CREATE DATABASE IF NOT EXISTS $TEST_DB;
USE $TEST_DB;
CREATE TABLE test_table (id INT, name STRING) USING PARQUET;
INSERT INTO test_table VALUES (1, 'Alice'), (2, 'Bob');
SELECT * FROM test_table;
"

# 测试6: 引擎管理
echo "测试6: 引擎管理测试"
$KYUUBI_HOME/bin/kyuubi-ctl list engine

# 测试7: REST API
echo "测试7: REST API测试"
curl -s -X GET "http://localhost:10099/api/v1/server/info" | jq '.'

echo "测试完成！"
```

## 结果分析和报告

### 性能基准
- **连接建立时间**: < 5秒
- **简单查询响应**: < 2秒  
- **复杂查询处理**: 根据数据量和复杂度变化
- **并发连接数**: 支持100+并发连接
- **内存使用**: 基础服务 < 1GB，引擎按需分配

### 故障排除指南
1. **服务启动失败**: 检查端口占用、Java版本、配置文件
2. **连接超时**: 验证网络连通性、防火墙设置
3. **SQL执行错误**: 检查Spark环境、资源配置
4. **性能问题**: 调整Spark参数、增加资源分配

### 监控建议
- 使用JMX或Prometheus监控关键指标
- 设置日志级别和轮转策略
- 定期检查引擎健康状态
- 监控资源使用情况

这个测试套件覆盖了Kyuubi 1.9.2的核心功能，可以有效验证系统的稳定性、性能和功能完整性。