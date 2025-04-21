#!/bin/bash

# mariadb_memory_monitor.sh
# A tool for monitoring MariaDB container memory usage and providing recommendations
# Usage: ./mariadb_memory_monitor.sh [options]
# Options:
#   -d <duration>    Monitoring duration in minutes (default: 5)
#   -i <interval>    Sampling interval in seconds (default: 10)
#   -o <file>       Output log file (default: ./mariadb_memory_YYYYMMDD_HHMMSS.log)
#   -q              Quiet mode - only output to log file
#   -h              Show this help message

# Default values
DURATION=5
INTERVAL=10
QUIET=false
LOG_DIR="$(dirname "$0")"
LOG_FILE="${LOG_DIR}/mariadb_memory_$(date +%Y%m%d_%H%M%S).log"
TOTAL_CONTAINERS=0
CURRENT_CONTAINER=0

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
    echo "  -o <file>       Output log file (default: ./mariadb_memory_YYYYMMDD_HHMMSS.log)"
    echo "  -q              Quiet mode - only output to log file"
    echo "  -h              Show this help message"
    echo
    echo "Example:"
    echo "  $0 -d 10 -i 5 -o ./memory_report.log  # Monitor for 10 minutes, 5-second intervals"
    exit 0
}

# Function to write to both console and log
log() {
    local message=$1
    local level=${2:-INFO}  # Default level is INFO
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Format the message with timestamp and level
    local formatted_message="[$timestamp] [$level] $message"
    
    # Write to log file
    echo "$formatted_message" >> "$LOG_FILE"
    
    # Write to console if not in quiet mode
    if [[ "$QUIET" != true ]]; then
        echo "$message"
    fi
}

# Function to create separator line
separator() {
    local char=${1:-"-"}
    local width=80
    printf -v line "%${width}s" ""
    echo "${line// /$char}"
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
while getopts "d:i:o:qh" opt; do
    case $opt in
        d) DURATION=$OPTARG ;;
        i) INTERVAL=$OPTARG ;;
        o) LOG_FILE=$OPTARG ;;
        q) QUIET=true ;;
        h) show_help ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Validate inputs
if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 1 ]]; then
    log "Error: Duration must be a positive integer" "ERROR"
    exit 1
fi

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
    log "Error: Interval must be a positive integer" "ERROR"
    exit 1
fi

# Calculate number of samples
SAMPLES=$(( (DURATION * 60) / INTERVAL ))

# Count total containers
TOTAL_CONTAINERS=$(docker ps --filter "ancestor=mariadb" --format "{{.Names}}" | wc -l)

log "Starting MariaDB memory monitoring"
log "Duration: $DURATION minutes, Interval: $INTERVAL seconds"
log "Found $TOTAL_CONTAINERS MariaDB containers"
log "Results will be saved to: $LOG_FILE"
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
    
    log "Monitoring $container..." "INFO"
    
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
            if [[ "$QUIET" != true ]]; then
                printf "\rProgress: %d/%d samples" "$i" "$SAMPLES"
            fi
        fi
        sleep "$INTERVAL"
    done
    [[ "$QUIET" != true ]] && echo
    
    # Calculate average memory usage
    local avg_memory=0
    if [[ $samples -gt 0 ]]; then
        avg_memory=$(echo "scale=2; $total_memory / $samples" | bc)
    fi
    
    echo "$max_memory $avg_memory"
}

# Summary variables
declare -A summary
summary["total_current_memory"]=0
summary["total_suggested_memory"]=0
summary["containers_need_increase"]=0
summary["containers_can_decrease"]=0

# Main monitoring loop
while read -r CONTAINER; do
    ((CURRENT_CONTAINER++))
    separator "="
    log "Container $CURRENT_CONTAINER of $TOTAL_CONTAINERS: $CONTAINER" "INFO"
    separator "-"
    
    # Get current settings
    current_mem_limit=$(get_memory_limit "$CONTAINER")
    current_buffer_pool=$(get_buffer_pool_size "$CONTAINER")
    
    # Get memory stats
    read -r max_mem avg_mem <<< "$(monitor_container "$CONTAINER")"
    
    # Round max memory to nearest 256MB
    suggested_limit=$(( ((max_mem * 1.5 + 255) / 256) * 256 ))
    
    # Calculate buffer pool size (60% of suggested limit)
    suggested_pool=$((suggested_limit * 60 / 100))
    
    # Log results
    log "Memory Statistics for $CONTAINER:"
    log "  Average Usage: ${avg_mem}MiB"
    log "  Peak Usage: ${max_mem}MiB"
    log ""
    log "Current Settings:"
    log "  Memory Limit: ${current_mem_limit}"
    log "  InnoDB Buffer Pool: ${current_buffer_pool}"
    log ""
    log "Recommendations:"
    log "  Suggested mem_limit: ${suggested_limit}m"
    log "  Suggested --innodb_buffer_pool_size=${suggested_pool}M"
    
    # Compare current vs suggested
    if [[ "$current_mem_limit" != "unlimited" ]]; then
        current_numeric=${current_mem_limit%M}
        if (( suggested_limit > current_numeric )); then
            ((summary["containers_need_increase"]++))
            log "⚠️  Warning: Memory increase recommended" "WARN"
            log "  Current: ${current_mem_limit}"
            log "  Recommended: ${suggested_limit}M"
            log "  Difference: +$((suggested_limit - current_numeric))M"
        elif (( suggested_limit < current_numeric )); then
            ((summary["containers_can_decrease"]++))
            log "💡 Note: Memory reduction possible" "INFO"
            log "  Current: ${current_mem_limit}"
            log "  Recommended: ${suggested_limit}M"
            log "  Potential savings: $((current_numeric - suggested_limit))M"
        fi
        
        # Update summary totals
        ((summary["total_current_memory"]+=current_numeric))
        ((summary["total_suggested_memory"]+=suggested_limit))
    fi
    log ""
done < <(docker ps --filter "ancestor=mariadb" --format "{{.Names}}")

# Print summary
separator "="
log "Summary Report" "INFO"
separator "-"
log "Total Containers Analyzed: $TOTAL_CONTAINERS"
log "Containers Needing More Memory: ${summary["containers_need_increase"]}"
log "Containers That Can Reduce Memory: ${summary["containers_can_decrease"]}"
log "Total Current Memory Allocation: ${summary["total_current_memory"]}M"
log "Total Suggested Memory Allocation: ${summary["total_suggested_memory"]}M"
log "Net Memory Change: $(( summary["total_suggested_memory"] - summary["total_current_memory"] ))M"
separator "="

log "Monitoring complete. Full results saved to: $LOG_FILE" "INFO"
