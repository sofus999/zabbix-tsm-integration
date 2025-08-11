#!/bin/bash
# Lightweight sequential script to check all instances every 10 minutes
# Enhanced with improved process management and error handling

# Setup logging
LOG_FILE="/var/log/zabbix/sp_volume_check.log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Script mutex
LOCK_FILE="/tmp/sp_volume_cron.lock"
if [ -e "${LOCK_FILE}" ]; then
    RUNNING_PID=$(cat "${LOCK_FILE}" 2>/dev/null)
    if ps -p $RUNNING_PID > /dev/null 2>&1; then
        echo "Script already running with PID $RUNNING_PID"
        exit 0
    else
        rm -f "${LOCK_FILE}"
    fi
fi
echo $$ > "${LOCK_FILE}"

# Configuration
TSM_USER="<TSM_MONITORING_USER>"
TSM_PASS="<TSM_MONITORING_PASSWORD>"
DSMADMC="/opt/tivoli/tsm/client/ba/bin/dsmadmc"
QUERY="SELECT access, COUNT(*) FROM volumes WHERE access<>'READWRITE' group by access"
GLOBAL_TIMEOUT=480  # 8 minutes maximum run time

# Default JSON template
DEFAULT_JSON='{
  "volumes": {
    "READONLY": 0,
    "OFFSITE": 0,
    "DESTROYED": 0,
    "UNAVAILABLE": 0,
    "UNKNOWN": 0
  }
}'

# Check if a PID is running
checkpid() {
    [ -d /proc/$1 ] && return 0
    return 1
}

# Enhanced cleanup function
cleanup_volume_check() {
    log "Running cleanup for volume check"
    
    # Remove lock file
    rm -f "${LOCK_FILE}"
    
    # Kill the timer process if running
    if [ -n "$TIMER_PID" ] && checkpid $TIMER_PID; then
        kill -9 $TIMER_PID 2>/dev/null
        log "Killed timer process $TIMER_PID"
    fi
    
    # Kill any dsmadmc process running our specific query
    for pid in $(pgrep -f "dsmadmc.*access.*volumes.*COUNT"); do
        kill -9 $pid 2>/dev/null
        log "Killed hanging process $pid"
    done
    
    # Kill any child processes that might be orphaned
    if [ -n "$cmd_pid" ] && checkpid $cmd_pid; then
        # Kill the main process
        kill -9 $cmd_pid 2>/dev/null
        log "Killed main dsmadmc process $cmd_pid"
        
        # Kill any children
        for child in $(pgrep -P $cmd_pid 2>/dev/null); do
            kill -9 $child 2>/dev/null
            log "Killed child process $child"
        done
    fi
    
    # Clean up temp files
    if [ -n "$tmp_file" ] && [ -f "$tmp_file" ]; then
        rm -f "$tmp_file"
    fi
    
    log "Cleanup completed"
}

# Register cleanup handler
trap cleanup_volume_check EXIT INT TERM HUP

# Start with background timer to ensure script ends
(
    sleep $GLOBAL_TIMEOUT
    if ps -p $$ > /dev/null; then
        log "WARNING: Script exceeded $GLOBAL_TIMEOUT seconds, killing"
        kill -15 $$
    fi
) &
TIMER_PID=$!

# Function to run query with improved handling
run_tsm_query() {
    local instance="$1"
    local output_file="$2"
    local timeout_val="$3"
    
    # Clear output file
    > "$output_file"
    
    # Run in background and track PID
    $DSMADMC -se="$instance" -id="$TSM_USER" -password="$TSM_PASS" \
        -dataonly=yes -commadelim "$QUERY" > "$output_file" 2>/dev/null &
    cmd_pid=$!
    
    # Wait for completion with timeout
    local wait_time=0
    while checkpid $cmd_pid; do
        if [ $wait_time -ge $timeout_val ]; then
            # Kill process and its children
            kill -9 $cmd_pid 2>/dev/null
            
            # Find and kill any child processes
            for child in $(pgrep -P $cmd_pid 2>/dev/null); do
                kill -9 $child 2>/dev/null
            done
            
            # Cleanup any related processes
            for pid in $(pgrep -f "dsmadmc.*$instance.*volumes"); do
                kill -9 $pid 2>/dev/null
            done
            
            return 124  # Timeout
        fi
        
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    # Check exit status
    wait $cmd_pid
    return $?
}

# Get all instances
ALL_INSTANCES=("rb0")
for i in $(seq -f "%02g" 1 98); do
    ALL_INSTANCES+=("rb$i")
done

log "Starting volume check for all instances"

# Process all instances sequentially
for instance in "${ALL_INSTANCES[@]}"; do
    # Check if we should skip based on connectivity
    if [ "$instance" = "rb0" ]; then
        instance_ip="10.255.1.100"
    else
        instance_num=${instance#rb}
        instance_num=${instance_num#0}
        instance_ip="10.255.1.$((100 + instance_num))"
    fi
    
    # Quick ping check to skip unresponsive servers
    if ! ping -c 1 -W 1 $instance_ip >/dev/null 2>&1; then
        log "Instance $instance not responding to ping, skipping"
        continue
    fi
    
    # Run query with improved handling
    tmp_file=$(mktemp)
    log "Querying $instance"
    
    run_tsm_query "$instance" "$tmp_file" 60
    result=$?
    
    # Initialize volume states
    declare -A volume_states
    volume_states["READONLY"]=0
    volume_states["OFFSITE"]=0
    volume_states["DESTROYED"]=0
    volume_states["UNAVAILABLE"]=0
    volume_states["UNKNOWN"]=0
    
    if [ $result -eq 0 ]; then
        # Success - parse results
        while IFS=',' read -r access count; do
            [[ -z "$access" || "$access" =~ ^ANR|^ANS ]] && continue
            access=${access// /}
            [[ -z "$access" ]] && continue
            
            # Clean up values
            count=${count// /}
            count=${count:-0}
            
            # Store in associative array (uppercase the key)
            access=$(echo "$access" | tr '[:lower:]' '[:upper:]')
            volume_states["$access"]=$count
            log "Instance $instance - found $count volumes with state $access"
        done < "$tmp_file"
    elif [ $result -eq 11 ]; then
        # No match - all volumes are READWRITE
        log "Instance $instance - all volumes are READWRITE"
    elif [ $result -eq 124 ]; then
        # Timeout
        log "Instance $instance - query timed out"
    else
        log "Instance $instance - error code $result"
    fi
    
    # Generate simple JSON with all states
    json=$(cat << EOF
{
  "volumes": {
    "READONLY": ${volume_states["READONLY"]},
    "OFFSITE": ${volume_states["OFFSITE"]},
    "DESTROYED": ${volume_states["DESTROYED"]},
    "UNAVAILABLE": ${volume_states["UNAVAILABLE"]},
    "UNKNOWN": ${volume_states["UNKNOWN"]}
  }
}
EOF
)
    
    # Send to Zabbix
    /usr/bin/zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -s "$instance" \
        -k storage_protect.volume.status -o "$json" > /dev/null 2>&1
    
    # Clean up
    rm -f "$tmp_file"
    
    # Sleep briefly between instances to prevent overloading
    sleep 1
done

# Kill background timer
kill $TIMER_PID 2>/dev/null

log "Volume check completed"
exit 0