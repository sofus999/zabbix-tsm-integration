#!/bin/bash
set -o pipefail

usage() {
    echo "Usage: $0 -i <instance> -u <username> -p <password>" >&2
    exit 1
}

while getopts "i:u:p:" opt; do
    case $opt in
        i) TSM_INSTANCE="$OPTARG" ;;
        u) TSM_USER="$OPTARG" ;;
        p) TSM_PASS="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$TSM_INSTANCE" || -z "$TSM_USER" || -z "$TSM_PASS" ]]; then
    usage
fi

# Check if wrapper exists
WRAPPER="/usr/lib/zabbix/externalscripts/storage_protect_dsmadmc.sh"
if [ ! -x "$WRAPPER" ]; then
    echo "{\"error\":\"Wrapper script not found or not executable\", \"data\":[]}" >&2
    exit 1
fi

# Run the query using wrapper
query="select SERVER_NAME, HL_ADDRESS, LL_ADDRESS from servers where (SERVER_NAME like 'RB__') or SERVER_NAME='RB0'"
result=$($WRAPPER -i "$TSM_INSTANCE" -u "$TSM_USER" -p "$TSM_PASS" -q "$query" -t 30)
wrapper_exit=$?

# Check for timeout or errors
if [ $wrapper_exit -ne 0 ]; then
    # The wrapper already outputs error info
    echo "{\"error\":\"Query failed with wrapper exit code $wrapper_exit\", \"data\":[]}" >&2
    exit 1
fi

# Start JSON output
echo "{"
echo "  \"data\": ["

first=1
# Use an associative array to skip duplicate server entries
declare -A seen

# Process each line of the output
while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue
    
    # Skip lines with ANR/ANS error messages
    [[ "$line" =~ ^ANR|^ANS ]] && continue
    
    # Split the line by commas
    IFS=',' read -r server ip port <<< "$line"
    
    # Clean up values (trim whitespace)
    server=$(echo "$server" | tr -d ' ')
    ip=$(echo "$ip" | tr -d ' ')
    port=$(echo "$port" | tr -d ' ')
    
    # Skip if any field is empty
    [[ -z "$server" || -z "$ip" || -z "$port" ]] && continue
    
    # Deduplicate: if we've seen this server before, skip it
    if [[ -n "${seen[$server]}" ]]; then
        continue
    fi
    seen[$server]=1
    
    # Convert server name to lowercase
    server=$(echo "$server" | tr '[:upper:]' '[:lower:]')
    
    # Add a comma before each entry except the first
    if [ $first -eq 1 ]; then
        first=0
    else
        echo "    ,"
    fi
    
    # Output the JSON object
    echo "    {\"{#SERVERNAME}\": \"$server\", \"{#ADDRESS}\": \"$ip\", \"{#PORT}\": \"$port\"}"
done <<< "$result"

# Finish JSON
echo ""
echo "  ]"
echo "}"

exit 0