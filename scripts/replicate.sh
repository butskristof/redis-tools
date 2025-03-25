#!/bin/bash

# Description:
#   This script replicates data from a source Redis cluster to a destination Redis instance.
#
# Usage:
#   ./replicate.sh [-s source-host] [-p source-port] [-a source-password] [-d dest-host] [-q dest-port] [-b dest-password]
#
# Options:
#   -s source-host      Source Redis host (default: localhost)
#   -p source-port      Source Redis port (default: 6379)
#   -a source-password  Source Redis password (optional)
#   -d dest-host        Destination Redis host (default: localhost)
#   -q dest-port        Destination Redis port (default: 6380)
#   -b dest-password    Destination Redis password (optional)
#
# Example:
#   ./replicate.sh -s redis-source.com -p 7001 -a sourcepass -d redis-dest.com -q 6380 -b destpass
#
# Dependencies:
#   - redis-cli and riot must be installed and available in the system PATH.

# Tools required for the script
REQUIRED_TOOLS=("redis-cli" "riot")

# Check if all required tools are installed
for TOOL in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$TOOL" &> /dev/null; then
        echo "Error: $TOOL is not installed or not available in PATH."
        exit 1
    fi
done

# Function to display usage information
usage() {
    echo "Usage: $0 [-s source-host] [-p source-port] [-a source-password] [-d dest-host] [-q dest-port] [-b dest-password]"
    echo "Options:"
    echo "  -s source-host      Source Redis host (default: localhost)"
    echo "  -p source-port      Source Redis port (default: 6379)"
    echo "  -a source-password  Source Redis password (optional)"
    echo "  -d dest-host        Destination Redis host (default: localhost)"
    echo "  -q dest-port        Destination Redis port (default: 6380)"
    echo "  -b dest-password    Destination Redis password (optional)"
    exit 1
}

# Default values
SOURCE_HOST="localhost"
SOURCE_PORT=6379
SOURCE_PASSWORD=""
DEST_HOST="localhost"
DEST_PORT=6380
DEST_PASSWORD=""

# Parse command line arguments
while getopts "s:p:a:d:q:b:" opt; do
    case ${opt} in
        s)
            SOURCE_HOST=$OPTARG
            ;;
        p)
            SOURCE_PORT=$OPTARG
            ;;
        a)
            SOURCE_PASSWORD=$OPTARG
            ;;
        d)
            DEST_HOST=$OPTARG
            ;;
        q)
            DEST_PORT=$OPTARG
            ;;
        b)
            DEST_PASSWORD=$OPTARG
            ;;
        \?)
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$SOURCE_HOST" ] || [ -z "$SOURCE_PORT" ] || [ -z "$DEST_HOST" ] || [ -z "$DEST_PORT" ]; then
    echo "Error: Missing required parameters."
    usage
fi


# Set authentication variables
SOURCE_AUTH=""
DEST_AUTH=""
if [ -n "$SOURCE_PASSWORD" ]; then
    SOURCE_AUTH="--source-pass $SOURCE_PASSWORD"
fi
if [ -n "$DEST_PASSWORD" ]; then
    DEST_AUTH="--target-pass $DEST_PASSWORD"
fi

# Get all primary nodes in the source cluster
PRIMARY_NODES=$(redis-cli -h "$SOURCE_HOST" -p "$SOURCE_PORT" ${SOURCE_PASSWORD:+-a "$SOURCE_PASSWORD" --no-auth-warning} cluster nodes | grep master | awk '{print $2}' | cut -d@ -f1)

# Loop over each primary node and replicate data
for NODE in $PRIMARY_NODES; do
    HOST=$(echo $NODE | cut -d: -f1)
    PORT=$(echo $NODE | cut -d: -f2)
    echo "Replicating from $HOST:$PORT to $DEST_HOST:$DEST_PORT"

    riot replicate redis://$HOST:$PORT redis://$DEST_HOST:$DEST_PORT $SOURCE_AUTH $DEST_AUTH
done

echo "Replication completed."
