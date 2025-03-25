#!/bin/bash

# Description:
#   This script connects to a Redis store and deletes all keys matching a specified pattern.
#   It supports both standalone instances and clusters.
#
# Usage:
#   ./delete-key-pattern.sh [-h host] [-p port] [-a password] <key-pattern>
#
# Options:
#   -h host      Redis host (default: localhost)
#   -p port      Redis port (default: 6379)
#   -a password  Redis password (optional)
#
# Arguments:
#   key-pattern  A pattern for the keys to be deleted.
#
# Example:
#   ./delete-key-pattern.sh -h redis.example.com -p 6380 -a mypassword 'user:*'
#
# Notes:
#   - The script uses SCAN to iterate through keys in standalone mode.
#   - In cluster mode, it identifies master nodes and deletes keys from each node.
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
    echo "Usage: $0 [-h host] [-p port] [-a password] <key-pattern>"
    echo "Options:"
    echo "  -h host      Redis host (default: localhost)"
    echo "  -p port      Redis port (default: 6379)"
    echo "  -a password  Redis password (optional)"
    echo "Example: $0 -h redis.example.com -p 6380 -a mypassword 'user:*'"
    exit 1
}

# Parse command line arguments
HOST=${REDIS_HOST:-"localhost"}
PORT=${REDIS_PORT:-6379}
AUTH=""

while getopts "h:p:a:" opt; do
    case ${opt} in
        h)
            HOST=$OPTARG
            ;;
        p)
            PORT=$OPTARG
            ;;
        a)
            AUTH="-a $OPTARG --no-auth-warning"
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

# Function to delete keys in standalone mode using KEYS
delete_standalone() {
    echo "Deleting keys matching pattern '$PATTERN' in standalone mode..."
    
    keys=$(redis-cli -h "$HOST" -p "$PORT" $AUTH KEYS "$PATTERN")
    if [ -n "$keys" ]; then
        # Build and batch execute DEL commands using --pipe
        for key in $keys; do
            printf "DEL %s\r\n" "$key"
        done | redis-cli -h "$HOST" -p "$PORT" $AUTH --pipe
    else
        echo "No keys match pattern '$PATTERN'."
    fi
}

# Function to delete keys in cluster mode
delete_cluster() {
    echo "Deleting keys matching pattern '$PATTERN' in cluster mode..."
    
    # Use cluster nodes to get all master nodes
    primary_nodes=$(redis-cli -h "$HOST" -p "$PORT" $AUTH cluster nodes | grep master | awk '{print $2}' | cut -d@ -f1)
    
    # Iterate through each master node
    for node in $primary_nodes; do
        echo "Processing node: $node"
        # Get host and port for the node
        node_host=$(echo $node | cut -d: -f1)
        node_port=$(echo $node | cut -d: -f2)

        keys=$(redis-cli -h "$node_host" -p "$node_port" $AUTH KEYS "$PATTERN")
        if [ -n "$keys" ]; then
            # Build and batch execute DEL commands using --pipe
            for key in $keys; do
                printf "DEL %s\r\n" "$key"
            done | redis-cli -h "$node_host" -p "$node_port" $AUTH --pipe
        else
            echo "No keys match pattern '$PATTERN'."
        fi
    done
}

# Main execution
echo "Starting key deletion for pattern: $PATTERN"
echo "Using Redis at $HOST:$PORT"

# Check Redis mode and execute appropriate deletion function
if is_cluster; then
    delete_cluster
else
    delete_standalone
fi

echo "Completed key deletion operation"