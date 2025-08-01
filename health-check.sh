#!/bin/bash
# Fixed health check script for Snowball Monitor

LOG_LOCATIONS=(
    "/var/log/snowball-monitor.log"
    "/opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log"
    "/tmp/snowball-monitor.log"
)

MAX_AGE_MINUTES=10

echo "=== Snowball Monitor Health Check ==="
echo "Time: $(date)"
echo ""

# Function to check a log file
check_log_file() {
    local log_file="$1"
    
    if [[ ! -f "$log_file" ]]; then
        return 1
    fi
    
    echo "Checking log file: $log_file"
    
    # Look for recent activity patterns
    # Check for any recent timestamp in the last few lines
    local recent_lines=$(tail -20 "$log_file" 2>/dev/null)
    
    if [[ -z "$recent_lines" ]]; then
        echo "  - Log file is empty"
        return 1
    fi
    
    # Look for various timestamp patterns
    local last_timestamp=""
    
    # Pattern 1: [YYYY-MM-DD HH:MM:SS] format from our enhanced script
    last_timestamp=$(echo "$recent_lines" | grep -o '\[[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\]' | tail -1 | tr -d '[]')
    
    # Pattern 2: "started at" or "finished at" format
    if [[ -z "$last_timestamp" ]]; then
        last_timestamp=$(echo "$recent_lines" | grep -o 'at [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}' | tail -1 | sed 's/at //')
    fi
    
    # Pattern 3: Simple date command output
    if [[ -z "$last_timestamp" ]]; then
        last_timestamp=$(echo "$recent_lines" | grep -oE '[A-Za-z]{3} [A-Za-z]{3} [0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2} [A-Z]{3} [0-9]{4}' | tail -1)
    fi
    
    if [[ -n "$last_timestamp" ]]; then
        echo "  - Last activity: $last_timestamp"
        
        # Try to convert to epoch time
        local last_epoch
        last_epoch=$(date -d "$last_timestamp" +%s 2>/dev/null)
        
        if [[ -n "$last_epoch" ]]; then
            local current_epoch=$(date +%s)
            local age_minutes=$(( (current_epoch - last_epoch) / 60 ))
            
            echo "  - Age: $age_minutes minutes"
            
            if [[ $age_minutes -le $MAX_AGE_MINUTES ]]; then
                echo "  - Status: HEALTHY"
                return 0
            else
                echo "  - Status: STALE (older than $MAX_AGE_MINUTES minutes)"
                return 1
            fi
        else
            echo "  - Could not parse timestamp, checking file modification time instead"
            local file_age_minutes=$(( ($(date +%s) - $(stat -c %Y "$log_file")) / 60 ))
            echo "  - File modified: $file_age_minutes minutes ago"
            
            if [[ $file_age_minutes -le $MAX_AGE_MINUTES ]]; then
                echo "  - Status: HEALTHY (based on file modification)"
                return 0
            else
                echo "  - Status: STALE (file not modified recently)"
                return 1
            fi
        fi
    else
        echo "  - No recognizable timestamps found"
        echo "  - Last few lines of log:"
        echo "$recent_lines" | tail -3 | sed 's/^/    /'
        return 1
    fi
}

# Check each potential log location
healthy_found=false

for log_file in "${LOG_LOCATIONS[@]}"; do
    if check_log_file "$log_file"; then
        healthy_found=true
        break
    fi
    echo ""
done

# Also check if the process might be running right now
echo "=== Process Check ==="
if pgrep -f "snowball-monitor.sh" > /dev/null; then
    echo "Monitoring script is currently running (PID: $(pgrep -f 'snowball-monitor.sh'))"
    healthy_found=true
else
    echo "Monitoring script is not currently running"
fi

echo ""
echo "=== Cron Status ==="
if systemctl is-active --quiet crond; then
    echo "Cron service is running"
    
    # Check recent cron activity
    local recent_cron=$(sudo journalctl -u crond --since "10 minutes ago" --no-pager -q 2>/dev/null | grep -i snowball)
    if [[ -n "$recent_cron" ]]; then
        echo "Recent cron activity found:"
        echo "$recent_cron" | tail -3 | sed 's/^/  /'
    else
        echo "No recent cron activity found for snowball jobs"
    fi
else
    echo "Cron service is NOT running!"
    healthy_found=false
fi

echo ""
echo "=== Overall Health Status ==="
if $healthy_found; then
    echo "✅ HEALTHY: Monitoring appears to be working"
    exit 0
else
    echo "❌ UNHEALTHY: No recent monitoring activity detected"
    echo ""
    echo "Troubleshooting suggestions:"
    echo "1. Check if cron job is configured: sudo crontab -l"
    echo "2. Run script manually: sudo /opt/snowball-monitor/snowball-monitor.sh"
    echo "3. Check cron logs: sudo journalctl -u crond -f"
    echo "4. Verify script is executable: ls -la /opt/snowball-monitor/snowball-monitor.sh"
    exit 1
fi
