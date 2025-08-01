# AWS Snowball Device Monitor

A lightweight, automated monitoring solution for AWS Snowball devices that provides real-time connectivity monitoring, alerting, and health tracking.

## What This Does

This project monitors the health and connectivity of AWS Snowball devices by periodically testing network connectivity and sending status updates to AWS CloudWatch. When a Snowball device becomes unreachable, the system automatically sends alerts via SNS, helping you quickly identify and respond to connectivity issues.

## How It Works

**Core Monitoring Process:**
1. **Connectivity Testing** - A bash script runs at regular intervals (every 1-5 minutes) to test network connectivity to your Snowball device using netcat
2. **Metrics Collection** - Results are sent to AWS CloudWatch as custom metrics (1 = online, 0 = offline)
3. **Intelligent Alerting** - CloudWatch alarms detect state changes and trigger SNS notifications only when status actually changes
4. **Health Monitoring** - Built-in health checks ensure the monitoring system itself is working properly

**Key Features:**
- ✅ **Zero false positives** - Only alerts on actual state changes, not transient network blips
- ✅ **Self-monitoring** - Includes health checks to ensure the monitor itself is running
- ✅ **Cost-effective** - Runs on a t3.nano instance (~$5/month total cost)
- ✅ **Production-ready** - Includes logging, error handling, and maintenance scripts
- ✅ **AWS-native** - Uses CloudWatch alarms for sophisticated alerting logic

## Use Cases

- **Data Migration Projects** - Monitor Snowball devices during large data transfers
- **Remote Locations** - Get instant alerts when devices at remote sites go offline
- **Compliance Requirements** - Maintain audit logs of device availability
- **Proactive Operations** - Detect connectivity issues before they impact your workflow

## Architecture

```
Snowball Device (10.42.0.53) ← [Network Test] ← EC2 Instance
                                                      ↓
CloudWatch Metrics ← [Status: 1=Online, 0=Offline] ←
        ↓
CloudWatch Alarms → SNS Topic → Email/SMS/Slack Alerts
```

The system is designed to be simple, reliable, and maintainable while providing enterprise-grade monitoring capabilities.

# Deployment Guide for Snowball Monitor

## Step 1: Create IAM Role for EC2 Instance

### Create IAM Policy for Snowball Monitoring
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CloudWatchMetrics",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        },
        {
            "Sid": "SNSPublish",
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "arn:aws:sns:us-east-1:151470012443:snow-updates"
        },
        {
            "Sid": "GetCallerIdentity",
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
```

### AWS CLI Commands to Create Role
```bash
# Create IAM policy
aws iam create-policy \
    --policy-name SnowballMonitoringPolicy \
    --policy-document file://snowball-policy.json

# Create IAM role for EC2
aws iam create-role \
    --role-name SnowballMonitoringRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ec2.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'

# Attach policy to role
aws iam attach-role-policy \
    --role-name SnowballMonitoringRole \
    --policy-arn arn:aws:iam::151470012443:policy/SnowballMonitoringPolicy

# Create instance profile
aws iam create-instance-profile \
    --instance-profile-name SnowballMonitoringProfile

# Add role to instance profile
aws iam add-role-to-instance-profile \
    --instance-profile-name SnowballMonitoringProfile \
    --role-name SnowballMonitoringRole
```

## Step 2: Launch EC2 Instance

### Instance Specifications
- **Instance Type**: `t3.nano` or `t3.micro` (sufficient for this script)
- **AMI**: Amazon Linux 2023 (latest)
- **VPC**: `vpc-00bce86d1dbe88c16` (your existing VPC)
- **Subnet**: Choose subnet that can reach `10.42.0.53`
- **IAM Instance Profile**: `SnowballMonitoringProfile`
- **Security Group**: Allow outbound only (no inbound needed)

### Launch Command
```bash
# Get latest Amazon Linux 2023 AMI ID
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*" "Name=state,Values=available" \
    --query 'Images|sort_by(@, &CreationDate)[-1].ImageId' \
    --output text)

# Launch instance
aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.nano \
    --key-name YOUR_KEY_PAIR \
    --security-group-ids sg-YOUR_SECURITY_GROUP \
    --subnet-id subnet-YOUR_SUBNET \
    --iam-instance-profile Name=SnowballMonitoringProfile \
    --user-data file://user-data.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=SnowballMonitor}]'
```

## Step 3: User Data Script for Initial Setup

Create `user-data.sh`:
```bash
#!/bin/bash
yum update -y
yum install -y nc bc aws-cli

# Create monitoring user
useradd -m -s /bin/bash snowball-monitor

# Create directories
mkdir -p /opt/snowball-monitor/logs
chown -R snowball-monitor:snowball-monitor /opt/snowball-monitor

# Set up log rotation
cat > /etc/logrotate.d/snowball-monitor << 'EOF'
/opt/snowball-monitor/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 snowball-monitor snowball-monitor
}
EOF

# Install Cron (This needs to be tested)
sudo yum install -y cronie cronie-anacron
sudo systemctl enable crond
sudo systemctl start crond

# Configure timezone (optional)
timedatectl set-timezone America/New_York
```

## Step 4: Deploy and Configure the Script

### SSH into the instance and set up the script:
```bash
# SSH to instance
ssh -i your-key.pem ec2-user@YOUR_INSTANCE_IP

# Switch to root for setup
sudo su -

# Create the monitoring script
cat > /opt/snowball-monitor/snowball-monitor.sh << 'EOF'
#!/bin/bash
# [Paste your enhanced script here]
EOF

# Make script executable
chmod +x /opt/snowball-monitor/snowball-monitor.sh
chown snowball-monitor:snowball-monitor /opt/snowball-monitor/snowball-monitor.sh

# Create wrapper script for cron with logging
cat > /opt/snowball-monitor/run-monitor.sh << 'EOF'
#!/bin/bash
SCRIPT_DIR="/opt/snowball-monitor"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/monitor-$(date +%Y%m%d).log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Run the monitoring script and log output
echo "=== Monitor run started at $(date) ===" >> "$LOG_FILE"
cd "$SCRIPT_DIR"
./snowball-monitor.sh >> "$LOG_FILE" 2>&1
EXIT_CODE=$?
echo "=== Monitor run finished at $(date) with exit code $EXIT_CODE ===" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

exit $EXIT_CODE
EOF

chmod +x /opt/snowball-monitor/run-monitor.sh
chown snowball-monitor:snowball-monitor /opt/snowball-monitor/run-monitor.sh
```

## Step 5: Set Up Cron Job

### Configure cron for the snowball-monitor user:
```bash
# Switch to monitoring user
sudo -u snowball-monitor crontab -e

# Add one of these cron entries:

# Every 1 minute
* * * * * /opt/snowball-monitor/run-monitor.sh

# Every 2 minutes  
*/2 * * * * /opt/snowball-monitor/run-monitor.sh

# Every 5 minutes
*/5 * * * * /opt/snowball-monitor/run-monitor.sh
```

### Verify cron is working:
```bash
# Check cron status
sudo systemctl status crond

# View cron logs
sudo tail -f /var/log/cron

# Check your monitoring logs
sudo tail -f /opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log
```

## Step 6: Create Monitoring and Alerting

### CloudWatch Agent (Optional but Recommended)
```bash
# Install CloudWatch agent
sudo yum install -y amazon-cloudwatch-agent

# Create config file
sudo cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/opt/snowball-monitor/logs/monitor-*.log",
                        "log_group_name": "/aws/ec2/snowball-monitor",
                        "log_stream_name": "{instance_id}",
                        "timezone": "Local"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "EC2/SnowballMonitor",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait"],
                "metrics_collection_interval": 300
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 300,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 300
            }
        }
    }
}
EOF

# Start CloudWatch agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s
```

## Step 7: Create Health Check Script

Create a health check for the monitoring process:
```bash
cat > /opt/snowball-monitor/health-check.sh << 'EOF'
#!/bin/bash
# Health check script

LOG_DIR="/opt/snowball-monitor/logs"
CURRENT_LOG="$LOG_DIR/monitor-$(date +%Y%m%d).log"
MAX_AGE_MINUTES=10

# Check if log file exists and has recent entries
if [[ -f "$CURRENT_LOG" ]]; then
    # Get last log entry timestamp
    LAST_RUN=$(grep "Monitor run started" "$CURRENT_LOG" | tail -1 | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}')
    
    if [[ -n "$LAST_RUN" ]]; then
        LAST_RUN_EPOCH=$(date -d "$LAST_RUN" +%s 2>/dev/null)
        CURRENT_EPOCH=$(date +%s)
        AGE_MINUTES=$(( (CURRENT_EPOCH - LAST_RUN_EPOCH) / 60 ))
        
        if [[ $AGE_MINUTES -le $MAX_AGE_MINUTES ]]; then
            echo "HEALTHY: Last run $AGE_MINUTES minutes ago"
            exit 0
        else
            echo "UNHEALTHY: Last run $AGE_MINUTES minutes ago (max: $MAX_AGE_MINUTES)"
            exit 1
        fi
    else
        echo "UNHEALTHY: Cannot parse last run time"
        exit 1
    fi
else
    echo "UNHEALTHY: No log file found"
    exit 1
fi
EOF

chmod +x /opt/snowball-monitor/health-check.sh
chown snowball-monitor:snowball-monitor /opt/snowball-monitor/health-check.sh

# Add health check to cron (every 15 minutes)
sudo -u snowball-monitor crontab -e
# Add this line:
# */15 * * * * /opt/snowball-monitor/health-check.sh >> /opt/snowball-monitor/logs/health-check.log 2>&1
```

## Step 8: Testing and Verification

### Test the setup:
```bash
# Test script manually
sudo -u snowball-monitor /opt/snowball-monitor/snowball-monitor.sh

# Test cron wrapper
sudo -u snowball-monitor /opt/snowball-monitor/run-monitor.sh

# Check logs
tail -n 50 /opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log

# Test health check
/opt/snowball-monitor/health-check.sh
```

### Monitor cron execution:
```bash
# Watch cron logs in real-time
sudo tail -f /var/log/cron

# Watch monitoring logs in real-time  
sudo tail -f /opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log

# Check last few cron executions
sudo grep snowball-monitor /var/log/cron | tail -10
```

## Step 9: Maintenance Scripts

### Create maintenance script:
```bash
cat > /opt/snowball-monitor/maintenance.sh << 'EOF'
#!/bin/bash
# Maintenance script for Snowball Monitor

echo "=== Snowball Monitor Maintenance ==="
echo "Date: $(date)"
echo ""

# Check disk usage
echo "Disk Usage:"
df -h /opt/snowball-monitor
echo ""

# Check log file sizes
echo "Log Files:"
find /opt/snowball-monitor/logs -name "*.log" -exec ls -lh {} \;
echo ""

# Check cron status
echo "Cron Service Status:"
systemctl is-active crond
echo ""

# Show recent cron jobs
echo "Recent Cron Executions:"
grep snowball-monitor /var/log/cron | tail -5
echo ""

# Check AWS connectivity
echo "AWS Connectivity Test:"
aws sts get-caller-identity --output table
echo ""

echo "=== Maintenance Complete ==="
EOF

chmod +x /opt/snowball-monitor/maintenance.sh
```

## Step 10: Cost Optimization

### Instance Scheduling (Optional)
If you want to save costs by stopping the instance during off-hours:

```bash
# Create start/stop scripts using AWS CLI or Lambda
# Example: Stop instance at 10 PM, start at 6 AM on weekdays only

# In Lambda or another scheduled service:
aws ec2 stop-instances --instance-ids i-your-instance-id  # 10 PM
aws ec2 start-instances --instance-ids i-your-instance-id  # 6 AM
```

## Monthly Costs Estimate

- **t3.nano instance**: ~$3.50/month (24/7)
- **EBS storage (8GB)**: ~$0.80/month  
- **CloudWatch logs**: ~$0.50/month
- **Data transfer**: ~$0.10/month
- **Total**: ~$4.90/month

## Troubleshooting Commands

```bash
# Check if script is running
ps aux | grep snowball-monitor

# Check cron jobs for user
sudo -u snowball-monitor crontab -l

# Check system logs
sudo journalctl -u crond -f

# Test network connectivity to Snowball
nc -zv 10.42.0.53 8443

# Check AWS permissions
aws sts get-caller-identity
aws cloudwatch put-metric-data --namespace "Test" --metric-data MetricName=Test,Value=1 --dry-run

# View full monitoring logs
less /opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log
```

This setup gives you a robust, monitored, and maintainable solution for running your Snowball monitoring script!
