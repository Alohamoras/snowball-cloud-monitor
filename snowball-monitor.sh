#!/bin/bash
# snowball-monitor.sh - Enhanced with verbose output

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Configuration
SNOWBALL_IP="10.42.0.53"
SNS_TOPIC="arn:aws:sns:us-east-1:151470012443:snow-updates"
TIMEOUT=5
SNOWBALL_PORT=8443

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print with timestamp and color
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Function to send CloudWatch metrics with error handling
send_metric() {
    local metric_value=$1
    local status_text=$2
    
    log_info "Sending CloudWatch metric: Status=$metric_value"
    
    if aws cloudwatch put-metric-data \
        --namespace "Snowball/Simple" \
        --metric-data MetricName=Status,Value=$metric_value,Unit=Count 2>/dev/null; then
        log_success "CloudWatch metric sent successfully ($status_text)"
    else
        log_error "Failed to send CloudWatch metric"
        return 1
    fi
}

# Function to send SNS alert with error handling
send_alert() {
    local message=$1
    
    log_info "Sending SNS alert to topic: ${SNS_TOPIC##*/}"  # Show just topic name
    log_info "Alert message: $message"
    
    if aws sns publish \
        --topic-arn "$SNS_TOPIC" \
        --message "$message" \
        --output text 2>/dev/null; then
        log_success "SNS alert sent successfully"
    else
        log_error "Failed to send SNS alert"
        return 1
    fi
}

# Function to check network connectivity with detailed output
check_connectivity() {
    log_info "Starting connectivity check for Snowball device"
    log_info "Target: $SNOWBALL_IP:$SNOWBALL_PORT"
    log_info "Timeout: ${TIMEOUT}s"
    
    # Record start time for performance measurement
    local start_time=$(date +%s.%N)
    
    # Test with netcat and capture both stdout and stderr
    if timeout $TIMEOUT nc -z -v $SNOWBALL_IP $SNOWBALL_PORT 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "N/A")
        
        log_success "Snowball is reachable at $SNOWBALL_IP:$SNOWBALL_PORT"
        log_info "Response time: ${duration}s"
        return 0
    else
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "N/A")
        
        log_error "Snowball is UNREACHABLE at $SNOWBALL_IP:$SNOWBALL_PORT"
        log_info "Failed after: ${duration}s"
        return 1
    fi
}

# Function to check AWS CLI availability
check_aws_cli() {
    log_info "Checking AWS CLI configuration..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    local aws_identity=$(aws sts get-caller-identity --output text --query 'Account' 2>/dev/null)
    log_success "AWS CLI configured (Account: $aws_identity)"
}

# Function to display script header
show_header() {
    echo "=============================================="
    echo "    Snowball Device Monitoring Script"
    echo "=============================================="
    echo "Target Device: $SNOWBALL_IP:$SNOWBALL_PORT"
    echo "SNS Topic: ${SNS_TOPIC##*/}"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=============================================="
    echo ""
}

# Main execution
main() {
    show_header
    
    # Pre-flight checks
    log_info "Performing pre-flight checks..."
    check_aws_cli
    
    # Check if required tools are available
    for tool in nc timeout bc; do
        if ! command -v $tool &> /dev/null; then
            log_warning "$tool not found, some features may not work optimally"
        fi
    done
    
    echo ""
    log_info "=== STARTING CONNECTIVITY CHECK ==="
    
    # Main connectivity check
    if check_connectivity; then
        echo ""
        log_info "=== DEVICE IS HEALTHY - SENDING SUCCESS METRICS ==="
        
        if send_metric 1 "online"; then
            log_success "✅ Monitoring cycle completed successfully"
        else
            log_warning "Device is online but metric sending failed"
            exit 1
        fi
        
    else
        echo ""
        log_info "=== DEVICE IS DOWN - SENDING FAILURE METRICS AND ALERTS ==="
        
        # Send failure metric
        local metric_sent=false
        if send_metric 0 "offline"; then
            metric_sent=true
        fi
        
        # Send alert
        local alert_message="❌ SNOWBALL ALERT: Device at $SNOWBALL_IP is unreachable as of $(date '+%Y-%m-%d %H:%M:%S')"
        local alert_sent=false
        if send_alert "$alert_message"; then
            alert_sent=true
        fi
        
        # Final status
        if $metric_sent && $alert_sent; then
            log_error "❌ Device is offline - metrics and alerts sent"
        elif $metric_sent; then
            log_error "❌ Device is offline - metrics sent, alert failed"
        else
            log_error "❌ Device is offline - failed to send metrics/alerts"
        fi
        
        exit 1
    fi
}

# Trap to handle script interruption
trap 'log_warning "Script interrupted by user"; exit 130' INT TERM

# Run main function
main

echo ""
log_info "=== MONITORING CYCLE COMPLETE ==="
echo "Finished: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="
