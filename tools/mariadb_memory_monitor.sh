#!/bin/bash

# mariadb_memory_monitor.sh
# A tool for monitoring MariaDB container memory usage and providing recommendations
# Usage: ./mariadb_memory_monitor.sh [options]
# Options:
#   -d <duration>    Monitoring duration in minutes (default: 5)
#   -i <interval>    Sampling interval in seconds (default: 10)
#   -h               Show this help message

# Default values
DURATION=5
INTERVAL=10

# Help function
show_help() {
    echo "MariaDB Memory Monitor"
    echo "======================"
    echo "A tool for monitoring MariaDB container memory usage and providing recommendations"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -d <duration>    Monitoring duration in minutes (default: 5)"
    echo "  -i <interval>    Sampling interval in seconds (default: 10)"
    echo "  -h               Show this help message"
    echo
    echo "Example:"
    echo "  $0 -d 10 -i 5    # Monitor for 10 minutes, sampling every 5 seconds"
    exit 0
}

# Function to get current memory limit
get_memory_limit() {
    local container=$1
    local mem_limit
    mem_limit=$(docker inspect "$container" --format '{{.HostConfig.Memory}}')
    
    # Convert bytes to MB if limit exists
    if [[ "$mem_limit" != "0" ]]; then
        echo "$((mem_limit / 1024 / 1024))M"
    else
        echo "unlimited"
    fi
}

# Function to get current InnoDB buffer pool size
get_buffer_pool_size() {
    local container=$1
    local buffer_size
    buffer_size=$(docker exec "$container" mysql -N -B -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" | awk '{print $2}')
    
    # Convert bytes to MB if value exists
    if [[ -n "$buffer_size" ]]; then
        echo "$((buffer_size / 1024 / 1024))M"
    else
        echo "unknown"
    fi
}

# Parse command line arguments
while getopts "d:i:h" opt; do
    case $opt in
        d) DURATION=$OPTARG ;;
        i) INTERVAL=$OPTARG ;;
        h) show_help ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Validate inputs
if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 1 ]]; then
    echo "Error: Duration must be a positive integer"
    exit 1
fi

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
    echo "Error: Interval must be a positive integer"
    exit 1
fi

# Calculate number of samples
SAMPLES=$(( (DURATION * 60) / INTERVAL ))

echo "Monitoring MariaDB containers for $DURATION minutes (sampling every $INTERVAL seconds)..."
echo

# Function to get memory usage
get_memory_usage() {
    local container=$1
    docker stats --no-stream --format "{{.MemUsage}}" "$container" | awk -F / '{print $1}' | sed 's/[^0-9.]//g'
}

# Function to monitor container for specified time
monitor_container() {
    local container=$1
    local max_memory=0
    local samples=0
    local total_memory=0
    
    echo "Monitoring $container..."
    
    # Monitor for specified duration
    for ((i=1; i<=SAMPLES; i++)); do
        current_mem=$(get_memory_usage "$container")
        if [[ "$current_mem" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            total_memory=$(echo "$total_memory + $current_mem" | bc)
            samples=$((samples + 1))
            
            # Update max memory if current is higher
            if (( $(echo "$current_mem > $max_memory" | bc -l) )); then
                max_memory=$current_mem
            fi
            
            # Show progress
            printf "\rProgress: %d/%d samples" "$i" "$SAMPLES"
        fi
        sleep "$INTERVAL"
    done
    echo
    
    # Calculate average memory usage
    local avg_memory=0
    if [[ $samples -gt 0 ]]; then
        avg_memory=$(echo "scale=2; $total_memory / $samples" | bc)
    fi
    
    echo "$max_memory $avg_memory"
}

# Main monitoring loop
docker ps --filter "ancestor=mariadb" --format "{{.Names}}" | while read CONTAINER; do
    echo "🔍 Container: $CONTAINER"
    
    # Get current settings
    current_mem_limit=$(get_memory_limit "$CONTAINER")
    current_buffer_pool=$(get_buffer_pool_size "$CONTAINER")
    
    # Get memory stats
    read -r max_mem avg_mem <<< "$(monitor_container "$CONTAINER")"
    
    # Round max memory to nearest 256MB
    local suggested_limit
    suggested_limit=$(( ((max_mem * 1.5 + 255) / 256) * 256 ))
    
    # Calculate buffer pool size (60% of suggested limit)
    local suggested_pool
    suggested_pool=$((suggested_limit * 60 / 100))
    
    echo "📊 Memory Statistics:"
    echo "   Average Usage: ${avg_mem}MiB"
    echo "   Peak Usage: ${max_mem}MiB"
    echo
    echo "⚙️  Current Settings:"
    echo "   Memory Limit: ${current_mem_limit}"
    echo "   InnoDB Buffer Pool: ${current_buffer_pool}"
    echo
    echo "📌 Recommendations:"
    echo "   Suggested mem_limit: ${suggested_limit}m"
    echo "   Suggested --innodb_buffer_pool_size=${suggested_pool}M"
    echo "   (Based on 1.5x peak usage, rounded to nearest 256MB)"
    echo
    if [[ "$current_mem_limit" != "unlimited" ]]; then
        current_numeric=${current_mem_limit%M}
        if (( suggested_limit > current_numeric )); then
            echo "⚠️  Warning: Recommended memory limit is higher than current setting"
            echo "   Current: ${current_mem_limit}"
            echo "   Recommended: ${suggested_limit}M"
            echo "   Difference: +$((suggested_limit - current_numeric))M"
        elif (( suggested_limit < current_numeric )); then
            echo "💡 Note: Current memory limit may be higher than needed"
            echo "   Current: ${current_mem_limit}"
            echo "   Recommended: ${suggested_limit}M"
            echo "   Potential savings: $((current_numeric - suggested_limit))M"
        fi
        echo
    fi
done

echo "Monitoring complete. Use these recommendations to update your .env file:"
echo "WP_MAX_MEMORY_LIMIT=<suggested_limit>M"
echo "WP_MEMORY_LIMIT=<suggested_limit/2>M"
echo
echo "Note: These are suggestions based on observed usage. Consider your host's"
echo "      total available memory when applying these values."
