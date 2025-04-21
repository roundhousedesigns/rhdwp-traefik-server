#!/bin/bash

# mariadb_memory_monitor.sh
# A tool for monitoring MariaDB container memory usage and providing recommendations
# Usage: ./mariadb_memory_monitor.sh [options]
# Options:
#   -d <duration>    Monitoring duration in minutes (default: 5)
#   -i <interval>    Sampling interval in seconds (default: 10)
#   -o <file>       Output log file (default: ./mariadb_memory_YYYYMMDD_HHMMSS.log)
#   -q              Quiet mode - only output to log file
#   -c              Current stats only - skip monitoring period
#   -h              Show this help message

# Default values
DURATION=5
INTERVAL=10
QUIET=false
CURRENT_ONLY=false
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
    echo "  -c              Current stats only - skip monitoring period"
    echo "  -h              Show this help message"
    echo
    echo "Example:"
    echo "  $0 -d 10 -i 5 -o ./memory_report.log  # Monitor for 10 minutes, 5-second intervals"
    echo "  $0 -c                                  # Show current stats only"
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
    
    # Get database credentials from container environment
    local db_user=$(docker inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep MYSQL_USER= | cut -d= -f2)
    local db_pass=$(docker inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep MYSQL_PASSWORD= | cut -d= -f2)
    local db_root_pass=$(docker inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep MYSQL_ROOT_PASSWORD= | cut -d= -f2)
    
    # Try with root password first, then user password
    if [[ -n "$db_root_pass" ]]; then
        buffer_size=$(docker exec "$container" mariadb -uroot -p"$db_root_pass" -N -B -e "SELECT @@innodb_buffer_pool_size;" 2>/dev/null)
    elif [[ -n "$db_user" && -n "$db_pass" ]]; then
        buffer_size=$(docker exec "$container" mariadb -u"$db_user" -p"$db_pass" -N -B -e "SELECT @@innodb_buffer_pool_size;" 2>/dev/null)
    else
        buffer_size=""
    fi
    
    # Convert bytes to MB if value exists and is numeric
    if [[ -n "$buffer_size" ]] && [[ "$buffer_size" =~ ^[0-9]+$ ]]; then
        # Convert bytes to MB (divide by 1024*1024)
        local mb_size=$((buffer_size / 1048576))
        echo "${mb_size}M"
    else
        # Try alternative method if first one fails
        if [[ -n "$db_root_pass" ]]; then
            buffer_size=$(docker exec "$container" mariadb -uroot -p"$db_root_pass" -N -B -e "SHOW VARIABLES WHERE Variable_name = 'innodb_buffer_pool_size';" | awk '{print $2}' 2>/dev/null)
        elif [[ -n "$db_user" && -n "$db_pass" ]]; then
            buffer_size=$(docker exec "$container" mariadb -u"$db_user" -p"$db_pass" -N -B -e "SHOW VARIABLES WHERE Variable_name = 'innodb_buffer_pool_size';" | awk '{print $2}' 2>/dev/null)
        fi
        
        if [[ -n "$buffer_size" ]] && [[ "$buffer_size" =~ ^[0-9]+$ ]]; then
            local mb_size=$((buffer_size / 1048576))
            echo "${mb_size}M"
        else
            echo "unknown"
        fi
    fi
}

# Function to get current memory usage
get_current_memory_usage() {
    local container=$1
    docker stats --no-stream --format "{{.MemUsage}}" "$container" | awk -F / '{print $1}' | sed 's/[^0-9.]//g'
}

# Function to calculate suggested memory limit
calculate_suggested_limit() {
    local current_mem=$1
    # Use bc for floating point calculations
    local suggested=$(echo "scale=0; ($current_mem * 1.5 + 255) / 256 * 256" | bc)
    echo "$suggested"
}

# Parse command line arguments
while getopts "d:i:o:qch" opt; do
    case $opt in
        d) DURATION=$OPTARG ;;
        i) INTERVAL=$OPTARG ;;
        o) LOG_FILE=$OPTARG ;;
        q) QUIET=true ;;
        c) CURRENT_ONLY=true ;;
        h) show_help ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Validate inputs
if [[ "$CURRENT_ONLY" != true ]]; then
    if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 1 ]]; then
        log "Error: Duration must be a positive integer" "ERROR"
        exit 1
    fi

    if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
        log "Error: Interval must be a positive integer" "ERROR"
        exit 1
    fi
fi

# Count total containers
TOTAL_CONTAINERS=$(docker ps --filter "ancestor=mariadb" --format "{{.Names}}" | wc -l)

if [[ "$CURRENT_ONLY" == true ]]; then
    log "Starting MariaDB current memory check"
else
    log "Starting MariaDB memory monitoring"
    log "Duration: $DURATION minutes, Interval: $INTERVAL seconds"
fi
log "Found $TOTAL_CONTAINERS MariaDB containers"
log "Results will be saved to: $LOG_FILE"
echo

# Function to monitor container for specified time
monitor_container() {
    local container=$1
    local max_memory=0
    local samples=0
    local total_memory=0
    
    # Monitor for specified duration
    for ((i=1; i<=SAMPLES; i++)); do
        current_mem=$(get_current_memory_usage "$container")
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
    
    if [[ "$CURRENT_ONLY" == true ]]; then
        # Get current memory usage only
        current_mem=$(get_current_memory_usage "$CONTAINER")
        max_mem=$current_mem
        avg_mem=$current_mem
    else
        # Calculate number of samples
        SAMPLES=$(( (DURATION * 60) / INTERVAL ))
        # Get memory stats from monitoring
        read -r max_mem avg_mem <<< "$(monitor_container "$CONTAINER")"
    fi
    
    # Calculate suggested memory limit using bc
    suggested_limit=$(calculate_suggested_limit "$max_mem")
    
    # Calculate buffer pool size (60% of suggested limit)
    suggested_pool=$(echo "scale=0; $suggested_limit * 60 / 100" | bc)
    
    # Log results
    log "Memory Statistics:"
    if [[ "$CURRENT_ONLY" == true ]]; then
        log "  Current Usage: ${current_mem}MiB"
    else
        log "  Average Usage: ${avg_mem}MiB"
        log "  Peak Usage: ${max_mem}MiB"
    fi
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
        if (( $(echo "$suggested_limit > $current_numeric" | bc -l) )); then
            ((summary["containers_need_increase"]++))
            log "⚠️  Warning: Memory increase recommended" "WARN"
            log "  Current: ${current_mem_limit}"
            log "  Recommended: ${suggested_limit}M"
            log "  Difference: +$(echo "$suggested_limit - $current_numeric" | bc)M"
        elif (( $(echo "$suggested_limit < $current_numeric" | bc -l) )); then
            ((summary["containers_can_decrease"]++))
            log "💡 Note: Memory reduction possible" "INFO"
            log "  Current: ${current_mem_limit}"
            log "  Recommended: ${suggested_limit}M"
            log "  Potential savings: $(echo "$current_numeric - $suggested_limit" | bc)M"
        fi
        
        # Update summary totals
        summary["total_current_memory"]=$(echo "${summary["total_current_memory"]} + $current_numeric" | bc)
        summary["total_suggested_memory"]=$(echo "${summary["total_suggested_memory"]} + $suggested_limit" | bc)
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
log "Net Memory Change: $(echo "${summary["total_suggested_memory"]} - ${summary["total_current_memory"]}" | bc)M"
separator "="

if [[ "$CURRENT_ONLY" == true ]]; then
    log "Current stats check complete. Full results saved to: $LOG_FILE" "INFO"
else
    log "Monitoring complete. Full results saved to: $LOG_FILE" "INFO"
fi
