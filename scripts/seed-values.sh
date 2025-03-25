#!/bin/bash

# Description:
#   This script connects to a Redis instance and creates a specified number of key-value pairs.
#   The keys are generated based on a user-provided pattern, and the values are random JSON objects.
#
# Usage:
#   ./create-values.sh [-h host] [-p port] [-a password] [-n count] <key-pattern>
#
# Options:
#   -h host      Redis host (default: localhost)
#   -p port      Redis port (default: 6379)
#   -a password  Redis password (optional)
#   -n count     Number of items to create (default: 10000)
#
# Arguments:
#   key-pattern  A pattern for the keys to be created. Use {num} in the pattern to insert a sequence number.
#
# Example:
#   ./create-values.sh -h redis.example.com -p 6380 -a mypassword -n 5000 'user:{num}'
#
# Notes:
#   - The script supports both standalone and cluster Redis modes.
#
# Dependencies:
#   - redis-cli must be installed and available in the system PATH.

# Tools required for the script
REQUIRED_TOOLS=("redis-cli")

# Check if all required tools are installed
for TOOL in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$TOOL" &> /dev/null; then
        echo "Error: $TOOL is not installed or not available in PATH."
        exit 1
    fi
done

# Function to display usage information
usage() {
    echo "Usage: $0 [-h host] [-p port] [-a password] [-n count] <key-pattern>"
    echo "Options:"
    echo "  -h host      Redis host (default: localhost)"
    echo "  -p port      Redis port (default: 6379)"
    echo "  -a password  Redis password (optional)"
    echo "  -n count     Number of items to create (default: 10000)"
    echo "Example: $0 -h redis.example.com -p 6380 -a mypassword -n 5000 'user:{num}'"
    echo "Note: Use {num} in your pattern to be replaced with the sequence number"
    exit 1
}

# Parse command line arguments
HOST=${REDIS_HOST:-"localhost"}
PORT=${REDIS_PORT:-6379}
AUTH=""
COUNT=10000

while getopts "h:p:a:n:" opt; do
    case ${opt} in
        h)
            HOST=$OPTARG
            ;;
        p)
            PORT=$OPTARG
            ;;
        a)
            AUTH="-a $OPTARG"
            ;;
        n)
            COUNT=$OPTARG
            ;;
        \?)
            usage
            ;;
    esac
done

# Shift past the last option to get the pattern
shift $((OPTIND -1))

# Check if a pattern argument is provided
if [ $# -ne 1 ]; then
    usage
fi

PATTERN=$1

# Function to check if Redis is in cluster mode
is_cluster() {
    cluster_info=$(redis-cli -h "$HOST" -p "$PORT" $AUTH cluster info 2>/dev/null)
    if [[ $cluster_info == *"cluster_state"* ]]; then
        return 0  # True - is a cluster
    else
        return 1  # False - not a cluster
    fi
}

# Function to generate a random JSON value
generate_json() {
    num=$1
    timestamp=$(date +%s)
    random_string=$(LC_ALL=C cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    echo "{\"id\":$num,\"timestamp\":$timestamp,\"data\":\"$random_string\"}"
}

# Function to generate key name from pattern
generate_key() {
    num=$1
    echo "${PATTERN/\{num\}/$num}"
}

# Function to create values
create_values() {
    local CLUSTER=""
    if is_cluster; then
        CLUSTER="-c"
        echo "Creating $COUNT values matching pattern '$PATTERN' in cluster mode..."
    else
        echo "Creating $COUNT values matching pattern '$PATTERN' in standalone mode..."
    fi
    
    for ((i=1; i<=COUNT; i++)); do
        key=$(generate_key "$i")
        value=$(generate_json "$i")
        redis-cli -h "$HOST" -p "$PORT" $AUTH $CLUSTER SET "$key" "$value"
        if [ $((i % 1000)) -eq 0 ]; then
            echo "Created $i values..."
        fi
    done
}

# Main execution
echo "Starting value creation with pattern: $PATTERN"
echo "Using Redis at $HOST:$PORT"

create_values

echo "Completed value creation operation"