#!/bin/bash
set -o pipefail

usage() {
   echo "Usage: $0 -i <TSM_INSTANCE> -u <TSM_USER> -p <TSM_PASS>" >&2
   exit 0
}

while getopts "i:u:p:" opt; do
   case "$opt" in
       i) TSM_INSTANCE="$OPTARG" ;;
       u) TSM_USER="$OPTARG" ;;
       p) TSM_PASS="$OPTARG" ;;
       *) usage ;;
   esac
done

if [ -z "$TSM_INSTANCE" ] || [ -z "$TSM_USER" ] || [ -z "$TSM_PASS" ]; then
   echo "{\"error\": \"Missing required arguments\"}"
   exit 0
fi

# Sanitize inputs to prevent injection
TSM_INSTANCE=$(echo "$TSM_INSTANCE" | tr -cd '[:alnum:].-')

# Function to check if a PID is running
checkpid() {
    [ -d /proc/$1 ] && return 0
    return 1
}

# Enhanced cleanup function
cleanup_pool_collector() {
    # Kill any hanging dsmadmc processes for this specific instance and query
    for pid in $(pgrep -f "dsmadmc.*$TSM_INSTANCE.*STGPOOLS"); do
        kill -9 $pid 2>/dev/null
    done
    
    # Kill the main process and any children
    if [ -n "$cmd_pid" ] && checkpid $cmd_pid; then
        kill -9 $cmd_pid 2>/dev/null
        
        for child in $(pgrep -P $cmd_pid 2>/dev/null); do
            kill -9 $child 2>/dev/null
        done
    fi
    
    # Remove temporary files
    if [ -n "$output_file" ] && [ -f "$output_file" ]; then
        rm -f "$output_file"
    fi
}

# Register cleanup handler
trap cleanup_pool_collector EXIT INT TERM HUP

# Function to run TSM command with reliable timeout handling
run_tsm_query() {
    local query="$1"
    local output_file="$2"
    local timeout_val="${3:-30}"
    
    # Clear the output file
    > "$output_file"
    
    # Execute dsmadmc in background and capture PID
    cd /opt/tivoli/tsm/client/ba/bin
    dsmadmc -se="$TSM_INSTANCE" -id="$TSM_USER" -password="$TSM_PASS" \
        -dataonly=yes -commadelim "$query" > "$output_file" 2>/dev/null &
    cmd_pid=$!
    
    # Wait for completion with timeout
    local wait_time=0
    while checkpid $cmd_pid; do
        if [ $wait_time -ge $timeout_val ]; then
            # Kill the main process
            kill -9 $cmd_pid 2>/dev/null
            
            # Find and kill any child processes
            for child in $(pgrep -P $cmd_pid 2>/dev/null); do
                kill -9 $child 2>/dev/null
            done
            
            # Cleanup any other related processes
            for pid in $(pgrep -f "dsmadmc.*$TSM_INSTANCE.*STGPOOLS"); do
                kill -9 $pid 2>/dev/null
            done
            
            return 124  # Timeout exit code
        fi
        
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    # Check the exit status
    wait $cmd_pid
    return $?
}

# Create temporary output file
output_file=$(mktemp)

# Query for storage pools
query="SELECT s.STGPOOL_NAME, s.DEVCLASS, s.STG_TYPE, s.PCT_UTILIZED, 
       s.EST_CAPACITY_MB, s.ACCESS, s.DESCRIPTION, s.POOLTYPE, s.REUSEDELAY 
       FROM STGPOOLS s"

# Run the query using our own reliable method
run_tsm_query "$query" "$output_file" 60
result=$?

# Process results
if [ $result -eq 124 ]; then
    # Timeout occurred
    echo "{\"error\": \"Query timed out after 60 seconds\", \"data_stgpool\": [], \"metrics_stgpool\": {}}"
    rm -f "$output_file"
    exit 0
elif [ $result -ne 0 ]; then
    # Other error
    error_msg=$(grep "ANR\|ANS" "$output_file" | head -1 | sed 's/^[^:]*: //')
    [ -z "$error_msg" ] && error_msg="Command failed with exit code $result"
    
    echo "{\"error\": \"$error_msg\", \"data_stgpool\": [], \"metrics_stgpool\": {}}"
    rm -f "$output_file"
    exit 0
fi

# Check for "no data" message
if grep -q "ANR2034E" "$output_file"; then
    # No data found is not an error, but return empty structure
    echo "{\"error\": \"\", \"data_stgpool\": [], \"metrics_stgpool\": {}}"
    rm -f "$output_file"
    exit 0
fi

# Process successful data
{
    echo "{"
    echo "  \"error\": \"\","
    echo "  \"data_stgpool\": ["
    
    first_pool=true
    while IFS=',' read -r name devclass type util cap access desc ptype reuse; do
        [[ -z "$name" || "$name" =~ ^ANR|^ANS ]] && continue
        name=${name// /}
        [[ -z "$name" ]] && continue
        
        [ "$first_pool" = true ] || echo ","
        first_pool=false
        printf '    {"{#POOLNAME}":"%s","{#ISMETADISK}":"%s"}' \
            "$name" "$([[ "$name" == *META-DISK ]] && echo "YES" || echo "NO")"
    done < "$output_file"
    
    echo -e "\n  ],"
    echo "  \"metrics_stgpool\": {"
    
    first_pool=true
    while IFS=',' read -r name devclass type util cap access desc ptype reuse; do
        [[ -z "$name" || "$name" =~ ^ANR|^ANS ]] && continue
        name=${name// /}
        [[ -z "$name" ]] && continue
        
        [ "$first_pool" = true ] || echo ","
        first_pool=false
        
        # Sanitize and clean values
        util="${util// /}"
        cap="${cap// /}"
        reuse="${reuse// /}"
        
        printf '    "%s":{"poolname":"%s","device":"%s","type":"%s","utilization":"%s","capacity":"%s","access":"%s","description":"%s","pooltype":"%s","reusedelay":"%s","is_meta_disk":"%s"}' \
            "$name" "$name" "${devclass// /}" "${type// /}" "${util:-0}" "${cap:-0}" "${access// /}" "${desc//\"/}" "${ptype// /}" "${reuse:-0}" \
            "$([[ "$name" == *META-DISK ]] && echo "YES" || echo "NO")"
    done < "$output_file"
    
    echo -e "\n  }"
    echo "}"
}

# Clean up
rm -f "$output_file"
exit 0