#!/bin/bash

# Description:
#   This script reads parameters from a YAML file and sets them in Redis as hash values.
#   If the key does not exist, it will be created. Otherwise, the values will be updated.
#   It supports both standalone instances and clusters.
#
# Usage:
#   ./create-params.sh [-h host] [-p port] [-a password] [-f yaml_file]
#
# Options:
#   -h host      Redis host (default: localhost)
#   -p port      Redis port (default: 6379)
#   -a password  Redis password (optional)
#   -f yaml_file Path to the YAML file containing parameters (default: params.yaml)
#
# Example:
#   ./create-params.sh -h redis.example.com -p 6380 -a mypassword -f config/params.yaml
#
# Notes:
#   - The script expects a YAML file with a specific structure (see params.yaml for example)
#   - In cluster mode, it correctly routes hash commands to the appropriate node
#
# Dependencies:
#   - redis-cli must be installed and available in the system PATH
#   - yq must be installed to parse YAML (https://github.com/mikefarah/yq)

# Tools required for the script
REQUIRED_TOOLS=("redis-cli" "yq")

# Check if all required tools are installed
for TOOL in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$TOOL" &> /dev/null; then
        echo "Error: $TOOL is not installed or not available in PATH."
        echo "Please install yq: https://github.com/mikefarah/yq"
        exit 1
    fi
done

# Function to display usage information
usage() {
    echo "Usage: $0 [-h host] [-p port] [-a password] [-f yaml_file]"
    echo "Options:"
    echo "  -h host      Redis host (default: localhost)"
    echo "  -p port      Redis port (default: 6379)"
    echo "  -a password  Redis password (optional)"
    echo "  -f yaml_file Path to the YAML file (default: params.yaml)"
    echo "Example: $0 -h redis.example.com -p 6380 -a mypassword -f config/params.yaml"
    exit 1
}

# Parse command line arguments
HOST=${REDIS_HOST:-"localhost"}
PORT=${REDIS_PORT:-6379}
AUTH=""
YAML_FILE="params.yaml"

while getopts "h:p:a:f:" opt; do
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
        f)
            YAML_FILE=$OPTARG
            ;;
        \?)
            usage
            ;;
    esac
done

# Check if the YAML file exists
if [ ! -f "$YAML_FILE" ]; then
    echo "Error: YAML file '$YAML_FILE' not found."
    exit 1
fi

# Function to check if Redis is in cluster mode
is_cluster() {
    cluster_info=$(redis-cli -h "$HOST" -p "$PORT" $AUTH cluster info 2>/dev/null)
    if [[ $cluster_info == *"cluster_state"* ]]; then
        return 0  # True - is a cluster
    else
        return 1  # False - not a cluster
    fi
}

# Function to set parameters in both standalone and cluster mode
set_params() {
    # Determine if Redis is running in cluster mode
    CLUSTER=""
    if is_cluster; then
        echo "Setting parameters in cluster mode..."
        CLUSTER="-c"
    fi
    
    # Get the number of elements in the YAML array
    length=$(yq -r 'length' "$YAML_FILE")
    
    # Process each key-values pair in the YAML file
    for (( i=0; i<$length; i++ )); do
        key=$(yq -r ".[$i].key" "$YAML_FILE")
        echo "Processing key: $key"
        
        # Build HSET commands for each key-value in the values map
        values=$(yq -r ".[$i].values | to_entries | .[] | \"HSET '$key' '\(.key)' '\(.value)'\"" "$YAML_FILE")
        
        # Execute each HSET command
        while read -r cmd; do
            if [ -n "$cmd" ]; then
                eval "redis-cli -h \"$HOST\" -p \"$PORT\" $CLUSTER $AUTH $cmd"
                echo "Set: $cmd"
            fi
        done <<< "$values"
    done
}

# Main execution
echo "Starting parameter import from: $YAML_FILE"
echo "Using Redis at $HOST:$PORT"

# Execute the unified function
set_params

echo "Completed parameter import"

