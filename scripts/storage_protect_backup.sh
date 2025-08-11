#!/bin/bash
set -o pipefail

usage() {
    echo "Usage: $0 -i <instance> -u <username> -p <password> -o <option>" >&2
    echo "Options:" >&2
    echo "  dbbackup     - Check database backup age" >&2
    echo "  restore      - Test restore functionality" >&2
    echo "  expiration   - Check last expiration time" >&2
    echo "  dbspace      - Check database space utilization" >&2
    echo "  logspace     - Check log space utilization" >&2
    exit 0
}

while getopts "i:u:p:o:" opt; do
    case $opt in
        i) TSM_INSTANCE="$OPTARG" ;;
        u) TSM_USER="$OPTARG" ;;
        p) TSM_PASS="$OPTARG" ;;
        o) CHECK_OPTION="$OPTARG" ;;
        ?) usage ;;
    esac
done

[[ -z "$TSM_INSTANCE" || -z "$TSM_USER" || -z "$TSM_PASS" || -z "$CHECK_OPTION" ]] && usage

# Check if wrapper exists
WRAPPER="/usr/lib/zabbix/externalscripts/storage_protect_dsmadmc.sh"
if [ ! -x "$WRAPPER" ]; then
    echo "Error: Wrapper script not found or not executable" >&2
    echo "0"  # Return safe default on error
    exit 0
fi

# Function to check if a PID is running
checkpid() {
    [ -d /proc/$1 ] && return 0
    return 1
}

# Function to run TSM queries with the wrapper
run_query() {
    local query="$1"
    local timeout="${2:-5}"
    
    $WRAPPER -i "$TSM_INSTANCE" -u "$TSM_USER" -p "$TSM_PASS" -q "$query" -t "$timeout" -f raw
    
    local result=$?
    if [ $result -ne 0 ]; then
        return 1
    fi
    
    return 0
}

case "$CHECK_OPTION" in
    "dbbackup")
        # Using exact query from original script
        SQL="select min(day(current_timestamp-end_time)) from summary where activity in ('FULL_DBBACKUP','INCR_DBBACKUP') and successful='YES' and end_time> current_timestamp - 28 days"
        
        result=$(run_query "$SQL" 6)
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            # Simple numeric output as in original script
            echo "$result" | tr -d ' ' | grep -E '^[0-9]+$' || echo "0"
        else
            echo "0"
        fi
        ;;

    "restore")
        TEST_FILE="/usr/lib/zabbix/externalscripts/storage_protect_backup.sh"
        RESTORE_OUT=$(mktemp)
        LOG_FILE=$(mktemp)
        
        # Function to cleanup all processes and files
        cleanup_restore() {
            # Kill the dsmc process and any children if still running
            if [ -n "$DSMC_PID" ] && checkpid $DSMC_PID; then
                kill -9 $DSMC_PID 2>/dev/null
                
                # Kill any child processes that might have been spawned
                for child in $(pgrep -P $DSMC_PID 2>/dev/null); do
                    kill -9 $child 2>/dev/null
                done
            fi
            
            # Find and kill any dsmc processes with our instance
            for pid in $(pgrep -f "dsmc.*$TSM_INSTANCE"); do
                kill -9 $pid 2>/dev/null
            done
            
            # Clean up temporary files
            rm -f "$RESTORE_OUT" "$LOG_FILE"
        }
        
        # Register cleanup on script exit
        trap cleanup_restore EXIT INT TERM HUP
        
        # Change to TSM client directory
        cd /opt/tivoli/tsm/client/ba/bin 2>/dev/null
        
        # Run dsmc in background and capture PID
        dsmc restore "$TEST_FILE" "$RESTORE_OUT" -server="$TSM_INSTANCE" -replace=all -latest -quiet > "$LOG_FILE" 2>&1 &
        DSMC_PID=$!
        
        # Wait for process to complete or timeout with active monitoring
        TIMEOUT=60
        wait_time=0
        while checkpid $DSMC_PID; do
            if [ $wait_time -ge $TIMEOUT ]; then
                echo "Restore timed out after $TIMEOUT seconds" >&2
                
                # Make this the return value
                echo "Restore timed out after $TIMEOUT seconds"
                exit 0
            fi
            
            sleep 1
            wait_time=$((wait_time + 1))
        done
        
        # Check dsmc exit status
        wait $DSMC_PID
        RESTORE_STATUS=$?
        
        # Copy log file contents to restore output for parsing if it's empty
        if [ ! -s "$RESTORE_OUT" ] && [ -s "$LOG_FILE" ]; then
            cat "$LOG_FILE" >> "$RESTORE_OUT"
        fi
        
        # Check for successful restore (contains specific text)
        if grep -q "Total number of objects restored:.*1" "$RESTORE_OUT"; then
            echo "1"  # Success
            exit 0
        fi
        
        # Check for specific ANS error messages
        ANS_ERROR=$(grep -m1 "ANS.*E" "$RESTORE_OUT" 2>/dev/null || true)
        if [ -n "$ANS_ERROR" ]; then
            # Return the exact error message
            echo "$ANS_ERROR"
            exit 0
        fi
        
        # If we get here, it's a failure without specific error code
        echo "Restore failed - No specific error code"
        exit 0
        ;;

    "expiration")
        SQL="SELECT CAST((CURRENT_TIMESTAMP - MAX(START_TIME)) SECONDS AS DECIMAL) AS seconds_since_exp
             FROM SUMMARY 
             WHERE ACTIVITY='EXPIRATION' 
             AND SUCCESSFUL='YES'"
        
        result=$(run_query "$SQL")
        if [ $? -eq 0 ]; then
            echo "${result:-0}" | tr -d ' ' | grep -E '^[0-9]+$' || echo "0"
        else
            echo "0"
        fi
        ;;
        
    "dbspace")
        SQL="select cast((100-(cast(sum(TOTAL_FS_SIZE_MB) as decimal(15,2))-cast(sum(USED_FS_SIZE_MB) as decimal(15,2)))/cast(sum(TOTAL_FS_SIZE_MB) as decimal(15,2))*100) as decimal (5,2)) from dbspace"
        result=$(run_query "$SQL")
        if [ $? -eq 0 ]; then
            echo "${result:-0}" | tr -d ' ' | grep -E '^[0-9.]+$' || echo "0"
        else
            echo "0"
        fi
        ;;

    "logspace")
        SQL="select cast(100*cast(USED_SPACE_MB as decimal(15,2))/cast(TOTAL_SPACE_MB as decimal(15,2)) as decimal(15,2)) from LOG"
        result=$(run_query "$SQL")
        if [ $? -eq 0 ]; then
            echo "${result:-0}" | tr -d ' ' | grep -E '^[0-9.]+$' || echo "0"
        else
            echo "0"
        fi
        ;;
    *)
        echo "Error: Invalid check option: $CHECK_OPTION" >&2
        echo "0"
        exit 0
        ;;
esac

exit 0