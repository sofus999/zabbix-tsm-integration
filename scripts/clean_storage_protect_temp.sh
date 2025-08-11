#!/bin/bash
# Add to crontab to run hourly

# Log file
LOG_FILE="/var/log/zabbix/tsm_cleanup.log"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting TSM temporary file cleanup"

# Find and count old lock files
LOCK_COUNT=$(find /tmp -name "dsmadmc_*.lock" -mmin +60 2>/dev/null | wc -l)
if [ $LOCK_COUNT -gt 0 ]; then
    log "Found $LOCK_COUNT stale lock files"
    find /tmp -name "dsmadmc_*.lock" -mmin +60 -delete 2>/dev/null
    log "Deleted $LOCK_COUNT stale lock files"
fi

# Find and count temporary files created by the script
TEMP_COUNT=$(find /tmp -name "tmp.*" -user zabbix -mmin +60 2>/dev/null | wc -l)
if [ $TEMP_COUNT -gt 0 ]; then
    log "Found $TEMP_COUNT stale temporary files"
    find /tmp -name "tmp.*" -user zabbix -mmin +60 -delete 2>/dev/null
    log "Deleted $TEMP_COUNT stale temporary files"
fi

# Clean up any hanging dsmadmc processes (over 60 minutes old)
PROCESS_COUNT=$(ps -eo pid,etimes,cmd | awk '$2 > 3600 && $3 ~ /dsmadmc/ {print $1}' | wc -l)
if [ $PROCESS_COUNT -gt 0 ]; then
    log "Found $PROCESS_COUNT hanging dsmadmc processes"
    ps -eo pid,etimes,cmd | awk '$2 > 3600 && $3 ~ /dsmadmc/ {print $1}' | xargs -r kill -9
    log "Killed $PROCESS_COUNT hanging processes"
fi

log "Cleanup completed"
exit 0