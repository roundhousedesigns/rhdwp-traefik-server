#!/bin/bash

# Replace set -e with more specific error handling
set +e          # Don't exit on all errors
set -u          # Exit on undefined variables
set -o pipefail # Exit on pipe failures

# Add a trap for error handling
trap 'echo "Error on line $LINENO. Exit code: $?" >&2' ERR

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
LOG_DIR="$(dirname "$(dirname "$0")")" # Go up one level from tools to project root
LOG_FILE="${LOG_DIR}/last-memory-audit.log"
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
    local level=${2:-INFO} # Default level is INFO

    # Format the message with level only
    local formatted_message="[$level] $message"

    # Write to log file (overwrite if first write, append otherwise)
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "$formatted_message" >"$LOG_FILE"
    else
        echo "$formatted_message" >>"$LOG_FILE"
    fi

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

    # Get the site directory from container labels
    local site_dir
    site_dir=$(docker inspect "$container" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}')
    local env_file="${site_dir}/.env"

    # Get WordPress scale from .env
    local wp_scale=1
    if [[ -f "$env_file" ]]; then
        wp_scale=$(grep WORDPRESS_SCALE= "$env_file" | cut -d= -f2)
        [[ -z "$wp_scale" ]] && wp_scale=1
    fi

    # Read credentials from site's .env file
    if [[ -f "$env_file" ]]; then
        local db_user
        local db_pass
        db_user=$(grep WORDPRESS_DB_USER= "$env_file" | cut -d= -f2)
        db_pass=$(grep WORDPRESS_DB_PASSWORD= "$env_file" | cut -d= -f2)

        # Get the buffer pool size using the database credentials
        buffer_size=$(docker exec "$container" mariadb -u "$db_user" -p"$db_pass" -N -B -e "SELECT @@innodb_buffer_pool_size;" 2>&1)
    else
        buffer_size=""
    fi

    # Check if we got a valid numeric value
    if [[ -n "$buffer_size" ]] && [[ "$buffer_size" =~ ^[0-9]+$ ]]; then
        # Convert bytes to MB (divide by 1024*1024)
        local mb_size=$((buffer_size / 1048576))
        echo "${mb_size}M"
    else
        echo "unknown"
    fi
}

# Function to get current memory usage
get_current_memory_usage() {
    local container=$1
    local usage

    # Get memory usage and clean up the output
    usage=$(docker stats --no-stream --format "{{.MemUsage}}" "$container" |
        awk -F'/' '{gsub(/MiB|GiB/, "", $1); gsub(/ /, "", $1); 
        if ($1 ~ /^[0-9.]+$/) print $1; else print "0"}')

    # Convert GiB to MiB if necessary
    if [[ "$usage" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$usage"
    else
        # If we still don't have a valid number, try a different format
        usage=$(docker stats --no-stream --format "{{.MemUsage}}" "$container" |
            awk '{gsub(/[^0-9.]/, "", $1); print $1}')
        if [[ "$usage" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "$usage"
        else
            echo "0"
        fi
    fi
}

# Function to calculate suggested memory limit
calculate_suggested_limit() {
    local current_mem=$1
    local wp_scale=$2

    # Validate inputs
    if ! [[ "$current_mem" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$wp_scale" =~ ^[0-9]+$ ]]; then
        echo "0"
        return 1
    fi

    # Use bc for floating point calculations
    local suggested
    suggested=$(echo "scale=2; ($current_mem * 1.5 + 255) / 256 * 256" | bc 2>/dev/null)
    if [[ -n "$suggested" ]]; then
        # Adjust for WordPress scale
        suggested=$(echo "scale=2; $suggested * $wp_scale" | bc 2>/dev/null)
        echo "${suggested:-0}"
    else
        echo "0"
    fi
}

# Function to get WordPress scale
get_wordpress_scale() {
    local container=$1
    local site_dir
    local env_file
    local wp_scale=1

    site_dir=$(docker inspect "$container" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}')
    env_file="${site_dir}/.env"

    if [[ -f "$env_file" ]]; then
        wp_scale=$(grep WORDPRESS_SCALE= "$env_file" | cut -d= -f2)
        [[ -z "$wp_scale" ]] && wp_scale=1
    fi

    echo "$wp_scale"
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
    \?)
        echo "Invalid option: -$OPTARG" >&2
        exit 1
        ;;
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

# Calculate number of samples
if [[ "$CURRENT_ONLY" != true ]]; then
    SAMPLES=$((DURATION * 60 / INTERVAL))
    log "Will take $SAMPLES samples at ${INTERVAL}s intervals over ${DURATION}m" "DEBUG"
fi

# Function to monitor container for specified time
monitor_container() {
    local container=$1
    local max_memory=0
    local samples=0
    local total_memory=0

    log "Monitoring $container..." "INFO"

    # Monitor for specified duration
    for ((i = 1; i <= SAMPLES; i++)); do
        local current_mem
        current_mem=$(get_current_memory_usage "$container")

        # Debug logging
        log "Sample $i: Raw memory value: $current_mem" "DEBUG"

        if [[ "$current_mem" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            total_memory=$(echo "$total_memory + $current_mem" | bc -l 2>/dev/null || echo "0")
            samples=$((samples + 1))

            # Update max memory if current is higher
            if (($(echo "$current_mem > $max_memory" | bc -l 2>/dev/null || echo "0"))); then
                max_memory=$current_mem
            fi

            # Show progress
            if [[ "$QUIET" != true ]]; then
                printf "\rSample %d/%d - Current: %.2fMiB, Max: %.2fMiB" "$i" "$SAMPLES" "$current_mem" "$max_memory"
            fi
        else
            log "Failed to get memory usage for sample $i (got: $current_mem)" "WARN"
        fi
        sleep "$INTERVAL"
    done
    [[ "$QUIET" != true ]] && echo

    # Calculate average memory usage
    local avg_memory=0
    if [[ $samples -gt 0 ]]; then
        avg_memory=$(echo "scale=2; $total_memory / $samples" | bc -l 2>/dev/null || echo "0")
    fi

    # Debug logging
    log "Final stats - Max: $max_memory, Avg: $avg_memory, Samples: $samples" "DEBUG"

    printf "%.2f %.2f" "$max_memory" "$avg_memory"
}

# Summary variables
declare -A summary
summary=([total_current_memory]=0 [total_suggested_memory]=0 [containers_need_increase]=0 [containers_can_decrease]=0)
CURRENT_CONTAINER=0

# Main monitoring loop
while read -r CONTAINER; do
    # Debug logging
    log "Processing container: $CONTAINER" "DEBUG"

    # Safer increment
    CURRENT_CONTAINER=$((CURRENT_CONTAINER + 1))
    log "Container count: $CURRENT_CONTAINER of $TOTAL_CONTAINERS" "DEBUG"

    separator "="
    log "Container $CURRENT_CONTAINER of $TOTAL_CONTAINERS: $CONTAINER" "INFO"
    separator "-"

    # Get current settings
    current_mem_limit=$(get_memory_limit "$CONTAINER")
    current_buffer_pool=$(get_buffer_pool_size "$CONTAINER")
    wp_scale=$(get_wordpress_scale "$CONTAINER")

    if [[ "$CURRENT_ONLY" == true ]]; then
        # Get current memory usage only
        current_mem=$(get_current_memory_usage "$CONTAINER")
        max_mem=$current_mem
        avg_mem=$current_mem
    else
        # Get memory stats from monitoring
        read -r max_mem avg_mem < <(monitor_container "$CONTAINER")
    fi

    # Ensure we have valid numbers
    [[ "$max_mem" =~ ^[0-9]+(\.[0-9]+)?$ ]] || max_mem=0
    [[ "$avg_mem" =~ ^[0-9]+(\.[0-9]+)?$ ]] || avg_mem=0

    # Calculate suggested memory limit using bc
    suggested_limit=$(calculate_suggested_limit "$max_mem" "$wp_scale")

    # Calculate buffer pool size (60% of suggested limit)
    suggested_pool=$(echo "scale=0; $suggested_limit * 60 / 100" | bc)

    # Log results
    log "Memory Statistics for $CONTAINER:"
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
    log "  WordPress Scale: ${wp_scale}"
    log ""
    log "Recommendations:"
    log "  Suggested mem_limit: ${suggested_limit}M"
    log "  Suggested --innodb_buffer_pool_size=${suggested_pool}M"

    # Compare current vs suggested
    if [[ "$current_mem_limit" != "unlimited" ]] && [[ "$suggested_limit" != "0" ]]; then
        current_numeric=${current_mem_limit%M}
        if (($(echo "$suggested_limit > $current_numeric" | bc -l 2>/dev/null || echo "0"))); then
            ((summary["containers_need_increase"]++))
            log "⚠️  Warning: Memory increase recommended" "WARN"
            log "  Current: ${current_mem_limit}"
            log "  Recommended: ${suggested_limit}M"
            log "  Difference: +$(echo "$suggested_limit - $current_numeric" | bc)M"
        elif (($(echo "$suggested_limit < $current_numeric" | bc -l 2>/dev/null || echo "0"))); then
            # Only suggest decrease if the difference is significant (>10%)
            if (($(echo "($current_numeric - $suggested_limit) / $current_numeric > 0.1" | bc -l 2>/dev/null || echo "0"))); then
                ((summary["containers_can_decrease"]++))
                log "💡 Note: Memory reduction possible" "INFO"
                log "  Current: ${current_mem_limit}"
                log "  Recommended: ${suggested_limit}M"
                log "  Potential savings: $(echo "$current_numeric - $suggested_limit" | bc)M"
            fi
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
