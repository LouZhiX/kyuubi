#!/bin/bash

# Kyuubi Knox Integration Deployment Script
# This script helps deploy Kyuubi with Knox integration

set -e

# Default values
KNOX_HOME=${KNOX_HOME:-"/opt/knox"}
KYUUBI_HOME=${KYUUBI_HOME:-$(cd "$(dirname "$0")/.." && pwd)}
KNOX_TOPOLOGY_NAME=${KNOX_TOPOLOGY_NAME:-"kyuubi"}
KYUUBI_HOST=${KYUUBI_HOST:-"localhost"}
KYUUBI_PORT=${KYUUBI_PORT:-"10099"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Knox is installed
check_knox_installation() {
    if [ ! -d "$KNOX_HOME" ]; then
        log_error "Knox installation not found at $KNOX_HOME"
        log_info "Please install Knox or set KNOX_HOME environment variable"
        exit 1
    fi
    
    if [ ! -f "$KNOX_HOME/bin/gateway.sh" ]; then
        log_error "Knox gateway script not found at $KNOX_HOME/bin/gateway.sh"
        exit 1
    fi
    
    log_info "Knox installation found at $KNOX_HOME"
}

# Deploy Knox topology
deploy_knox_topology() {
    log_info "Deploying Knox topology for Kyuubi..."
    
    # Create topology directory if it doesn't exist
    mkdir -p "$KNOX_HOME/conf/topologies"
    
    # Copy topology file
    if [ -f "$KYUUBI_HOME/conf/knox-topology.xml.template" ]; then
        cp "$KYUUBI_HOME/conf/knox-topology.xml.template" "$KNOX_HOME/conf/topologies/$KNOX_TOPOLOGY_NAME.xml"
        
        # Replace placeholders
        sed -i "s|http://localhost:10099|http://$KYUUBI_HOST:$KYUUBI_PORT|g" "$KNOX_HOME/conf/topologies/$KNOX_TOPOLOGY_NAME.xml"
        
        log_info "Knox topology deployed to $KNOX_HOME/conf/topologies/$KNOX_TOPOLOGY_NAME.xml"
    else
        log_error "Knox topology template not found at $KYUUBI_HOME/conf/knox-topology.xml.template"
        exit 1
    fi
}

# Deploy Knox descriptor
deploy_knox_descriptor() {
    log_info "Deploying Knox descriptor for Kyuubi..."
    
    # Create descriptors directory if it doesn't exist
    mkdir -p "$KNOX_HOME/conf/descriptors"
    
    # Copy descriptor file
    if [ -f "$KYUUBI_HOME/conf/knox-descriptor.json.template" ]; then
        cp "$KYUUBI_HOME/conf/knox-descriptor.json.template" "$KNOX_HOME/conf/descriptors/kyuubi.json"
        
        # Replace placeholders
        sed -i "s|0.0.0.0:10099|$KYUUBI_HOST:$KYUUBI_PORT|g" "$KNOX_HOME/conf/descriptors/kyuubi.json"
        
        log_info "Knox descriptor deployed to $KNOX_HOME/conf/descriptors/kyuubi.json"
    else
        log_error "Knox descriptor template not found at $KYUUBI_HOME/conf/knox-descriptor.json.template"
        exit 1
    fi
}

# Configure Kyuubi for Knox integration
configure_kyuubi() {
    log_info "Configuring Kyuubi for Knox integration..."
    
    # Create Kyuubi configuration
    cat > "$KYUUBI_HOME/conf/kyuubi-knox.conf" << EOF
# Kyuubi Knox Integration Configuration

# Enable Knox integration
kyuubi.knox.integration.enabled=true

# Knox Gateway URL (update this with your Knox Gateway URL)
kyuubi.knox.gateway.url=https://localhost:8443

# Knox topology name
kyuubi.knox.topology.name=$KNOX_TOPOLOGY_NAME

# Knox service path
kyuubi.knox.service.path=/kyuubi

# Enable SSL for Knox
kyuubi.knox.ssl.enabled=true

# Enable authentication for Knox
kyuubi.knox.authentication.enabled=true

# Knox proxy users
kyuubi.knox.proxy.users=knox

# Enable REST protocol
kyuubi.frontend.protocols=REST

# REST service configuration
kyuubi.frontend.rest.bind.port=$KYUUBI_PORT
kyuubi.frontend.bind.host=0.0.0.0

# Enable CORS for Knox integration
kyuubi.frontend.rest.cors.enabled=true
kyuubi.frontend.rest.cors.allowed.origins=*
kyuubi.frontend.rest.cors.allowed.methods=GET,POST,PUT,DELETE,OPTIONS
kyuubi.frontend.rest.cors.allowed.headers=*
EOF
    
    log_info "Kyuubi Knox configuration created at $KYUUBI_HOME/conf/kyuubi-knox.conf"
}

# Start Knox Gateway
start_knox() {
    log_info "Starting Knox Gateway..."
    
    if [ -f "$KNOX_HOME/bin/gateway.sh" ]; then
        cd "$KNOX_HOME"
        ./bin/gateway.sh start
        
        # Wait for Knox to start
        sleep 10
        
        # Check if Knox is running
        if curl -k -s "https://localhost:8443/gateway/admin/api/v1/version" > /dev/null 2>&1; then
            log_info "Knox Gateway started successfully"
        else
            log_warn "Knox Gateway may not be fully started yet"
        fi
    else
        log_error "Knox gateway script not found"
        exit 1
    fi
}

# Start Kyuubi
start_kyuubi() {
    log_info "Starting Kyuubi with Knox integration..."
    
    if [ -f "$KYUUBI_HOME/bin/kyuubi" ]; then
        cd "$KYUUBI_HOME"
        
        # Start Kyuubi with Knox configuration
        ./bin/kyuubi start --conf conf/kyuubi-knox.conf
        
        # Wait for Kyuubi to start
        sleep 10
        
        # Check if Kyuubi is running
        if curl -s "http://$KYUUBI_HOST:$KYUUBI_PORT/api/v1/info" > /dev/null 2>&1; then
            log_info "Kyuubi started successfully"
        else
            log_warn "Kyuubi may not be fully started yet"
        fi
    else
        log_error "Kyuubi script not found"
        exit 1
    fi
}

# Test integration
test_integration() {
    log_info "Testing Knox-Kyuubi integration..."
    
    # Test Knox Gateway
    if curl -k -s "https://localhost:8443/gateway/admin/api/v1/version" > /dev/null 2>&1; then
        log_info "✓ Knox Gateway is accessible"
    else
        log_error "✗ Knox Gateway is not accessible"
        return 1
    fi
    
    # Test Kyuubi directly
    if curl -s "http://$KYUUBI_HOST:$KYUUBI_PORT/api/v1/info" > /dev/null 2>&1; then
        log_info "✓ Kyuubi is accessible directly"
    else
        log_error "✗ Kyuubi is not accessible directly"
        return 1
    fi
    
    # Test Kyuubi through Knox
    if curl -k -s "https://localhost:8443/gateway/$KNOX_TOPOLOGY_NAME/kyuubi/api/v1/info" > /dev/null 2>&1; then
        log_info "✓ Kyuubi is accessible through Knox"
    else
        log_warn "✗ Kyuubi is not accessible through Knox (may need authentication)"
    fi
    
    log_info "Integration test completed"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  deploy     - Deploy Knox topology and descriptor"
    echo "  configure  - Configure Kyuubi for Knox integration"
    echo "  start      - Start both Knox and Kyuubi"
    echo "  test       - Test the integration"
    echo "  all        - Deploy, configure, start, and test"
    echo ""
    echo "Environment variables:"
    echo "  KNOX_HOME           - Knox installation directory (default: /opt/knox)"
    echo "  KYUUBI_HOME         - Kyuubi installation directory (default: script directory)"
    echo "  KNOX_TOPOLOGY_NAME  - Knox topology name (default: kyuubi)"
    echo "  KYUUBI_HOST         - Kyuubi host (default: localhost)"
    echo "  KYUUBI_PORT         - Kyuubi port (default: 10099)"
    echo ""
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 all"
    echo "  KNOX_HOME=/opt/knox KYUUBI_HOST=kyuubi.example.com $0 all"
}

# Main function
main() {
    case "${1:-}" in
        "deploy")
            check_knox_installation
            deploy_knox_topology
            deploy_knox_descriptor
            ;;
        "configure")
            configure_kyuubi
            ;;
        "start")
            start_knox
            start_kyuubi
            ;;
        "test")
            test_integration
            ;;
        "all")
            check_knox_installation
            deploy_knox_topology
            deploy_knox_descriptor
            configure_kyuubi
            start_knox
            start_kyuubi
            sleep 15
            test_integration
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"