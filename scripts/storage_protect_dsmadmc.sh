[root@scnmzabdkhos011 externalscripts]# cat storage_protect_dsmadmc.sh
#!/bin/bash
# storage_protect_dsmadmc.sh - A wrapper script for dsmadmc calls
# Handles timeouts and process termination

set -o pipefail

# Default settings
TIMEOUT=30
RETRIES=0
DEBUG=0
FORMAT="default"  # Options: default, raw, csv, json, zabbix

usage() {
    echo "Usage: $0 -i <instance> -u <username> -p <password> -q <query> [-t <timeout>] [-r <retries>] [-f <format>] [-d]" >&2
    echo
    echo "Options:" >&2
    echo "  -i <instance>   : TSM instance name or address" >&2
    echo "  -u <username>   : TSM username" >&2
    echo "  -p <password>   : TSM password" >&2
    echo "  -q <query>      : TSM query to execute" >&2
    echo "  -t <timeout>    : Timeout in seconds (default: 30)" >&2
    echo "  -r <retries>    : Number of retries on failure (default: 0)" >&2
    echo "  -f <format>     : Output format (default, raw, csv, json, zabbix)" >&2
    echo "                    zabbix: Returns '0' for 'no data' results" >&2
    echo "  -d              : Debug mode (shows command execution)" >&2
    exit 1
}

# Check if a PID is running
checkpid() {
    [ -d /proc/$1 ] && return 0
    return 1
}

# Parse command line options
while getopts "i:u:p:q:t:r:f:d" opt; do
    case "$opt" in
        i) TSM_INSTANCE="$OPTARG" ;;
        u) TSM_USER="$OPTARG" ;;
        p) TSM_PASS="$OPTARG" ;;
        q) TSM_QUERY="$OPTARG" ;;
        t) TIMEOUT="$OPTARG" ;;
        r) RETRIES="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        d) DEBUG=1 ;;
        *) usage ;;
    esac
done

# Validate required parameters
if [[ -z "$TSM_INSTANCE" || -z "$TSM_USER" || -z "$TSM_PASS" || -z "$TSM_QUERY" ]]; then
    usage
fi

# Validate numeric parameters
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
    echo "Error: Timeout must be a number" >&2
    exit 1
fi

if ! [[ "$RETRIES" =~ ^[0-9]+$ ]]; then
    echo "Error: Retries must be a number" >&2
    exit 1
fi

# Validate format option
if ! [[ "$FORMAT" =~ ^(default|raw|csv|json|zabbix)$ ]]; then
    echo "Error: Invalid format option: $FORMAT" >&2
    echo "Valid options: default, raw, csv, json, zabbix" >&2
    exit 1
fi

# Sanitize inputs to prevent injection
TSM_INSTANCE=$(echo "$TSM_INSTANCE" | tr -cd '[:alnum:].-')

# Check if we can access the client directory
if ! cd /opt/tivoli/tsm/client/ba/bin 2>/dev/null; then
    echo "Error: Failed to access TSM directory" >&2
    if [ "$FORMAT" = "zabbix" ]; then
        echo "0"
    fi
    exit 4
fi

# Create temporary files
output_file=$(mktemp)
error_file=$(mktemp)

# Define cleanup function
cleanup() {
    rm -f "$output_file" "$error_file"
    
    # Find and kill any stuck processes that we started
    if [ -n "$session_pid" ] && kill -0 $session_pid 2>/dev/null; then
        kill -9 $session_pid 2>/dev/null
    fi
}

# Register cleanup handler for normal and abnormal termination
trap cleanup EXIT INT TERM HUP

# Execute the query with retry logic
attempt=0
success=0

while [ $attempt -le $RETRIES ]; do
    if [ $attempt -gt 0 ]; then
        sleep 1  # Wait before retry
    fi
    
    # Increment attempt counter
    ((attempt++))
    
    # Show command if in debug mode
    if [ $DEBUG -eq 1 ]; then
        echo "Executing: dsmadmc -se=\"$TSM_INSTANCE\" -id=\"$TSM_USER\" -password=*** -dataonly=yes -commadelim \"$TSM_QUERY\"" >&2
    fi
    
    # Execute with timeout
    timeout -k 5 $TIMEOUT dsmadmc -se="$TSM_INSTANCE" -id="$TSM_USER" -password="$TSM_PASS" \
        -dataonly=yes -commadelim "$TSM_QUERY" > "$output_file" 2> "$error_file" &
    session_pid=$!
    
    wait $session_pid
    result=$?
    
    # Check result codes
    if [ $result -eq 124 ] || [ $result -eq 137 ]; then
        # Timeout occurred (124) or process was killed (137)
        if [ $attempt -le $RETRIES ]; then
            echo "Warning: Query timed out after $TIMEOUT seconds. Retry $attempt of $RETRIES..." >&2
            # Make sure the process is fully terminated
            pkill -f "dsmadmc.*$TSM_INSTANCE.*$TSM_QUERY" 2>/dev/null
            continue
        fi
        
        echo "Error: Query timed out after $TIMEOUT seconds" >&2
        if [ "$FORMAT" = "zabbix" ]; then
            echo "0"
        fi
        exit 2
    elif [ $result -ne 0 ]; then
        # Command failed
        if [ -s "$error_file" ]; then
            error_msg=$(grep -m 1 "ANS\|ANR" "$error_file" | tr -d '\r\n"')
        else
            error_msg=$(grep -m 1 "ANS\|ANR" "$output_file" | tr -d '\r\n"')
        fi
        
        # No data is not an error for ANR2034E (no match found)
        if [[ -n "$error_msg" && "$error_msg" =~ ANR2034E ]]; then
            # For zabbix format, return just "0" for no data
            if [ "$FORMAT" = "zabbix" ]; then
                echo "0"
                exit 0
            fi
            
            # For other formats, passthrough the output
            cat "$output_file"
            exit 0
        fi
        
        # If no specific error message found, use generic one
        if [ -z "$error_msg" ]; then
            error_msg="Command failed with exit code $result"
        fi
        
        if [ $attempt -le $RETRIES ]; then
            echo "Warning: $error_msg. Retry $attempt of $RETRIES..." >&2
            continue
        fi
        
        echo "Error: $error_msg" >&2
        if [ "$FORMAT" = "zabbix" ]; then
            echo "0"
        fi
        exit 3
    else
        # Command succeeded
        # Check for "no match found" in the output
        if grep -q "ANR2034E" "$output_file" || grep -q "ANR2034E" "$error_file"; then
            if [ "$FORMAT" = "zabbix" ]; then
                echo "0"
                exit 0
            fi
        fi
        
        # Output results
        cat "$output_file"
        exit 0
    fi
done

# If we reached here, it means we've exhausted all retries
echo "Error: Maximum retries exceeded" >&2
if [ "$FORMAT" = "zabbix" ]; then
    echo "0"
fi
exit 3