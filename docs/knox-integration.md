# Apache Knox Integration with Kyuubi WebUI

This document describes how to integrate Apache Kyuubi 1.9 with Apache Knox gateway to provide secure, centralized access to Kyuubi WebUI through the Knox proxy.

## Overview

Apache Knox is a REST API gateway for interacting with Apache Hadoop clusters. By integrating Kyuubi with Knox, you can:

- Provide secure, centralized access to Kyuubi WebUI through Knox gateway
- Leverage Knox's authentication and authorization capabilities
- Enable single sign-on (SSO) for Kyuubi WebUI
- Support high availability and load balancing for multiple Kyuubi instances
- Implement fine-grained access control policies

## Architecture

```
Client Browser
      ↓
Knox Gateway (https://knox-server:8443)
      ↓
Kyuubi Server(s) (http://kyuubi-server:10099)
      ↓
Kyuubi WebUI
```

## Prerequisites

- Apache Knox 1.6.0 or later
- Apache Kyuubi 1.9.0 or later
- Java 8 or later
- Network connectivity between Knox gateway and Kyuubi servers

## Configuration

### 1. Kyuubi Configuration

Add the following configuration to your `kyuubi-defaults.conf`:

```properties
# Enable Knox proxy integration
kyuubi.frontend.knox.proxy.enabled=true

# Knox gateway URL (adjust to your Knox server)
kyuubi.frontend.knox.gateway.url=https://knox-server.example.com:8443

# Knox service and topology names
kyuubi.frontend.knox.service.name=KYUUBI
kyuubi.frontend.knox.topology.name=kyuubi

# Knox context path for Kyuubi WebUI
kyuubi.frontend.knox.context.path=/kyuubi

# Enable Knox authentication integration
kyuubi.frontend.knox.authentication.enabled=true

# Knox authentication headers
kyuubi.frontend.knox.principal.header=SM_USER
kyuubi.frontend.knox.groups.header=SM_GROUPS

# REST frontend configuration (ensure it's enabled)
kyuubi.frontend.protocols=THRIFT_BINARY,REST
kyuubi.frontend.rest.bind.host=0.0.0.0
kyuubi.frontend.rest.bind.port=10099
```

### 2. Knox Service Definition

Copy the provided `service.xml` file to your Knox installation:

```bash
# Copy the Kyuubi service definition
cp conf/knox/service.xml $KNOX_HOME/data/services/kyuubi/1.9.0/service.xml
```

The service definition file defines how Knox routes requests to Kyuubi and handles URL rewriting.

### 3. Knox Topology Configuration

Copy and customize the provided `topology.xml` file:

```bash
# Copy the topology configuration
cp conf/knox/topology.xml $KNOX_HOME/conf/topologies/kyuubi.xml
```

Edit the topology file to match your environment:

- Update LDAP/Kerberos authentication settings
- Modify Kyuubi server URLs
- Adjust authorization policies
- Configure high availability settings

### 4. Knox Gateway Configuration

Add the following to your Knox `gateway-site.xml`:

```xml
<configuration>
    <!-- Enable Knox gateway -->
    <property>
        <name>gateway.port</name>
        <value>8443</value>
    </property>
    
    <!-- SSL configuration -->
    <property>
        <name>gateway.gateway.conf.dir</name>
        <value>conf</value>
    </property>
    
    <!-- Enable service discovery -->
    <property>
        <name>gateway.service.discovery.enabled</name>
        <value>true</value>
    </property>
</configuration>
```

## Deployment Steps

### 1. Deploy Knox Service Definition

```bash
# Create service directory structure
mkdir -p $KNOX_HOME/data/services/kyuubi/1.9.0

# Copy service definition
cp conf/knox/service.xml $KNOX_HOME/data/services/kyuubi/1.9.0/

# Verify service definition
ls -la $KNOX_HOME/data/services/kyuubi/1.9.0/
```

### 2. Deploy Knox Topology

```bash
# Copy topology configuration
cp conf/knox/topology.xml $KNOX_HOME/conf/topologies/kyuubi.xml

# Customize topology for your environment
vi $KNOX_HOME/conf/topologies/kyuubi.xml
```

### 3. Restart Knox Gateway

```bash
# Stop Knox gateway
$KNOX_HOME/bin/gateway.sh stop

# Start Knox gateway
$KNOX_HOME/bin/gateway.sh start

# Verify Knox is running
curl -k https://knox-server:8443/gateway/admin/api/v1/topologies
```

### 4. Configure and Start Kyuubi

```bash
# Update Kyuubi configuration
vi $KYUUBI_HOME/conf/kyuubi-defaults.conf

# Start Kyuubi server
$KYUUBI_HOME/bin/kyuubi start
```

## Accessing Kyuubi WebUI through Knox

Once configured, you can access Kyuubi WebUI through Knox at:

```
https://knox-server.example.com:8443/gateway/kyuubi/kyuubi/ui/
```

### URL Structure

- **Knox Gateway**: `https://knox-server:8443`
- **Gateway Path**: `/gateway/{topology-name}`
- **Service Path**: `/{service-context-path}`
- **WebUI Path**: `/ui/`

## Authentication and Authorization

### LDAP Authentication

Knox supports LDAP authentication out of the box. Configure your LDAP settings in the topology file:

```xml
<param>
    <name>main.ldapContextFactory.url</name>
    <value>ldap://your-ldap-server:389</value>
</param>
<param>
    <name>main.ldapRealm.userSearchBase</name>
    <value>ou=people,dc=example,dc=com</value>
</param>
```

### Kerberos Authentication

For Kerberos authentication, configure the HadoopAuth provider:

```xml
<provider>
    <role>authentication</role>
    <name>HadoopAuth</name>
    <enabled>true</enabled>
    <param>
        <name>hadoop.auth.config.type</name>
        <value>kerberos</value>
    </param>
</provider>
```

### Authorization

Configure access control using the AclsAuthz provider:

```xml
<provider>
    <role>authorization</role>
    <name>AclsAuthz</name>
    <enabled>true</enabled>
    <param>
        <name>kyuubi.acl</name>
        <value>admin;kyuubi-users;data-analysts</value>
    </param>
</provider>
```

## High Availability Configuration

Knox supports high availability for Kyuubi services. Configure multiple Kyuubi server URLs in the topology:

```xml
<service>
    <role>KYUUBI</role>
    <url>http://kyuubi-server1.example.com:10099</url>
    <url>http://kyuubi-server2.example.com:10099</url>
    <url>http://kyuubi-server3.example.com:10099</url>
    
    <param>
        <name>ha.enabled</name>
        <value>true</value>
    </param>
    <param>
        <name>ha.maxFailoverAttempts</name>
        <value>3</value>
    </param>
</service>
```

## Monitoring and Health Checks

### Knox Health Checks

Knox provides health check endpoints:

```bash
# Check Knox gateway status
curl -k https://knox-server:8443/gateway/admin/api/v1/topologies/kyuubi

# Check Kyuubi service health through Knox
curl -k https://knox-server:8443/gateway/kyuubi/kyuubi/health
```

### Kyuubi Service Info

Get Kyuubi service information through Knox:

```bash
curl -k https://knox-server:8443/gateway/kyuubi/kyuubi/service-info
```

## Troubleshooting

### Common Issues

#### 1. 404 Not Found Error

**Symptom**: Accessing Kyuubi WebUI through Knox returns 404 error.

**Solution**:
- Verify Knox service definition is correctly deployed
- Check topology configuration
- Ensure Kyuubi server is running and accessible
- Verify URL paths match the configuration

#### 2. Authentication Failures

**Symptom**: Cannot authenticate through Knox.

**Solution**:
- Check LDAP/Kerberos configuration in topology
- Verify user credentials and permissions
- Check Knox gateway logs for authentication errors
- Ensure authentication headers are correctly configured

#### 3. Proxy Errors

**Symptom**: Knox cannot proxy requests to Kyuubi.

**Solution**:
- Verify network connectivity between Knox and Kyuubi
- Check Kyuubi REST service is enabled and accessible
- Review Knox gateway logs for proxy errors
- Ensure firewall rules allow traffic

### Log Files

#### Knox Logs
```bash
# Knox gateway logs
tail -f $KNOX_HOME/logs/gateway.log

# Knox audit logs
tail -f $KNOX_HOME/logs/gateway-audit.log
```

#### Kyuubi Logs
```bash
# Kyuubi server logs
tail -f $KYUUBI_HOME/logs/kyuubi-server-*.log
```

### Debug Configuration

Enable debug logging for Knox:

```xml
<!-- In $KNOX_HOME/conf/gateway-log4j.properties -->
log4j.logger.org.apache.knox.gateway=DEBUG
log4j.logger.org.apache.knox.gateway.dispatch=DEBUG
```

Enable debug logging for Kyuubi Knox integration:

```properties
# In kyuubi-defaults.conf
kyuubi.frontend.knox.proxy.enabled=true
# Add to log4j2.xml
<Logger name="org.apache.kyuubi.server.ui" level="DEBUG"/>
```

## Security Considerations

### SSL/TLS Configuration

Always use HTTPS for Knox gateway in production:

```xml
<property>
    <name>gateway.port</name>
    <value>8443</value>
</property>
<property>
    <name>gateway.https.port</name>
    <value>8443</value>
</property>
```

### Network Security

- Use firewall rules to restrict access to Knox gateway
- Ensure Kyuubi servers are not directly accessible from external networks
- Use VPN or private networks for Knox-to-Kyuubi communication

### Authentication Security

- Use strong authentication mechanisms (LDAP, Kerberos)
- Implement proper session timeout policies
- Enable audit logging for security monitoring

## Performance Tuning

### Knox Configuration

```xml
<!-- Increase connection pool sizes -->
<param>
    <name>httpclient.maxConnections</name>
    <value>100</value>
</param>
<param>
    <name>httpclient.connectionTimeout</name>
    <value>5000</value>
</param>
```

### Kyuubi Configuration

```properties
# Increase REST service thread pool
kyuubi.frontend.rest.max.worker.threads=200
kyuubi.frontend.rest.min.worker.threads=10
```

## Migration Guide

### From Direct Access to Knox Proxy

1. **Backup existing configuration**:
   ```bash
   cp $KYUUBI_HOME/conf/kyuubi-defaults.conf kyuubi-defaults.conf.backup
   ```

2. **Update Kyuubi configuration** with Knox settings

3. **Test Knox integration** in a staging environment

4. **Update client access URLs** to use Knox gateway

5. **Monitor and validate** the integration

## Support and Resources

- [Apache Knox Documentation](https://knox.apache.org/)
- [Apache Kyuubi Documentation](https://kyuubi.apache.org/)
- [Knox Service Definition Reference](https://knox.apache.org/books/knox-1-6-0/user-guide.html#Service+Definitions)
- [Knox Topology Configuration](https://knox.apache.org/books/knox-1-6-0/user-guide.html#Topologies)

## Example Scripts

### Knox Service Health Check Script

```bash
#!/bin/bash
# knox-health-check.sh

KNOX_URL="https://knox-server.example.com:8443"
TOPOLOGY="kyuubi"

# Check Knox gateway
echo "Checking Knox gateway..."
curl -k -s "$KNOX_URL/gateway/admin/api/v1/topologies" > /dev/null
if [ $? -eq 0 ]; then
    echo "Knox gateway is accessible"
else
    echo "Knox gateway is not accessible"
    exit 1
fi

# Check Kyuubi service through Knox
echo "Checking Kyuubi service through Knox..."
curl -k -s "$KNOX_URL/gateway/$TOPOLOGY/kyuubi/health" > /dev/null
if [ $? -eq 0 ]; then
    echo "Kyuubi service is accessible through Knox"
else
    echo "Kyuubi service is not accessible through Knox"
    exit 1
fi

echo "All health checks passed"
```

### Knox Configuration Validation Script

```bash
#!/bin/bash
# validate-knox-config.sh

KNOX_HOME=${KNOX_HOME:-/opt/knox}
TOPOLOGY_NAME="kyuubi"

echo "Validating Knox configuration for Kyuubi integration..."

# Check service definition
if [ -f "$KNOX_HOME/data/services/kyuubi/1.9.0/service.xml" ]; then
    echo "✓ Kyuubi service definition found"
else
    echo "✗ Kyuubi service definition not found"
    exit 1
fi

# Check topology configuration
if [ -f "$KNOX_HOME/conf/topologies/$TOPOLOGY_NAME.xml" ]; then
    echo "✓ Kyuubi topology configuration found"
else
    echo "✗ Kyuubi topology configuration not found"
    exit 1
fi

# Check Knox gateway configuration
if [ -f "$KNOX_HOME/conf/gateway-site.xml" ]; then
    echo "✓ Knox gateway configuration found"
else
    echo "✗ Knox gateway configuration not found"
    exit 1
fi

echo "Knox configuration validation completed"
```