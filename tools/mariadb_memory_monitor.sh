#!/bin/bash
# mariadb_memory_monitor.sh
# A tool for monitoring MariaDB container memory usage and providing recommendations
#
# Usage: ./mariadb_memory_monitor.sh [options]
# Options:
#   -d <duration>    Monitoring duration in minutes (default: 5)
#   -i <interval>    Sampling interval in seconds (default: 10)
#   -o <file>       Output log file (default: ./last-memory-audit.log)
#   -q              Quiet mode - only output to log file
#   -c              Current stats only - skip monitoring period
#   -v              Verbose/debug mode
#   -h              Show this help message

# Source the main library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/rhdwp-lib.sh" || source "/workspace/lib/rhdwp-lib.sh"
source "${SCRIPT_DIR}/../lib/rhdwp-docker.sh" 2>/dev/null || source "/workspace/lib/rhdwp-docker.sh"

# Default values
DURATION=5
INTERVAL=10
QUIET=false
CURRENT_ONLY=false
LOG_DIR="$(dirname "$(dirname "$0")")" # Go up one level from tools to project root
LOG_FILE="${LOG_DIR}/last-memory-audit.log"
TOTAL_CONTAINERS=0
CURRENT_CONTAINER=0

# Custom log function that writes to both console and file
# Args: message (string), level (string, optional)
log_to_file() {
	local message="$1"
	local level="${2:-INFO}"
	local timestamp
	
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	
	# Write to log file
	if [[ ! -f "$LOG_FILE" ]]; then
		echo "[$timestamp] [$level] $message" > "$LOG_FILE"
	else
		echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
	fi
	
	# Also use standard logging (respects quiet mode)
	case "$level" in
		ERROR|FATAL)
			rhdwp_log_error "$message"
			;;
		WARN)
			rhdwp_log_warn "$message"
			;;
		DEBUG)
			rhdwp_log_debug "$message"
			;;
		*)
			if [[ "$QUIET" != "true" ]]; then
				rhdwp_log_info "$message"
			fi
			;;
	esac
}

# Function to create separator line
# Args: char (string, optional)
separator() {
	local char="${1:--}"
	local width=80
	printf -v line "%${width}s" ""
	echo "${line// /$char}"
}

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
	echo "  -o <file>       Output log file (default: ./last-memory-audit.log)"
	echo "  -q              Quiet mode - only output to log file"
	echo "  -c              Current stats only - skip monitoring period"
	echo "  -v              Verbose/debug mode"
	echo "  -h              Show this help message"
	echo
	echo "Example:"
	echo "  $0 -d 10 -i 5 -o ./memory_report.log  # Monitor for 10 minutes, 5-second intervals"
	echo "  $0 -c                                  # Show current stats only"
	exit 0
}

# Parse command line arguments
while getopts "d:i:o:qcvh" opt; do
	case $opt in
		d)
			DURATION="$OPTARG"
			;;
		i)
			INTERVAL="$OPTARG"
			;;
		o)
			LOG_FILE="$OPTARG"
			;;
		q)
			QUIET=true
			;;
		c)
			CURRENT_ONLY=true
			;;
		v)
			rhdwp_enable_verbose
			;;
		h)
			show_help
			;;
		\?)
			rhdwp_log_error "Invalid option: -$OPTARG"
			exit 1
			;;
	esac
done

# Validate inputs
if [[ "$CURRENT_ONLY" != true ]]; then
	if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 1 ]]; then
		log_to_file "Error: Duration must be a positive integer" "ERROR"
		exit 1
	fi
	
	if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
		log_to_file "Error: Interval must be a positive integer" "ERROR"
		exit 1
	fi
fi

# Initialize
rhdwp_init "mariadb_memory_monitor"

# Check required commands
rhdwp_require_command docker || exit 1
rhdwp_require_command bc || exit 1
rhdwp_require_command jq || exit 1

# Check Docker is running
rhdwp_docker_is_running || exit 1

# Count total containers
TOTAL_CONTAINERS=$(docker ps --filter "ancestor=mariadb" --format "{{.Names}}" | wc -l)

if [[ "$CURRENT_ONLY" == true ]]; then
	log_to_file "Starting MariaDB current memory check"
else
	log_to_file "Starting MariaDB memory monitoring"
	log_to_file "Duration: $DURATION minutes, Interval: $INTERVAL seconds"
fi
log_to_file "Found $TOTAL_CONTAINERS MariaDB containers"
log_to_file "Results will be saved to: $LOG_FILE"
echo

# Function to get current memory limit
# Args: container (string)
# Returns: memory limit via echo
get_memory_limit() {
	local container="$1"
	local mem_limit
	
	if ! rhdwp_docker_container_exists "$container"; then
		log_to_file "Container not found: $container" "ERROR"
		echo "unknown"
		return 1
	fi
	
	mem_limit=$(rhdwp_docker_inspect "$container" "{{.HostConfig.Memory}}")
	
	# Convert bytes to MB if limit exists
	if [[ "$mem_limit" != "0" ]] && [[ -n "$mem_limit" ]]; then
		echo "$((mem_limit / 1024 / 1024))M"
	else
		echo "unlimited"
	fi
}

# Function to get current InnoDB buffer pool size
# Args: container (string)
# Returns: buffer pool size via echo
get_buffer_pool_size() {
	local container="$1"
	local buffer_size
	local site_dir
	local env_file
	local db_user
	local db_pass
	
	# Get the site directory from container labels
	site_dir=$(rhdwp_docker_inspect "$container" '{{index .Config.Labels "com.docker.compose.project.working_dir"}}')
	env_file="${site_dir}/.env"
	
	# Read credentials from site's .env file
	if [[ ! -f "$env_file" ]]; then
		echo "unknown"
		return 1
	fi
	
	# Parse .env file safely
	db_user=$(grep "^WORDPRESS_DB_USER=" "$env_file" | cut -d= -f2 | tr -d '"' | tr -d "'" || echo "")
	db_pass=$(grep "^WORDPRESS_DB_PASSWORD=" "$env_file" | cut -d= -f2 | tr -d '"' | tr -d "'" || echo "")
	
	if [[ -z "$db_user" ]] || [[ -z "$db_pass" ]]; then
		echo "unknown"
		return 1
	fi
	
	# Get the buffer pool size using the database credentials
	if ! rhdwp_docker_container_is_running "$container"; then
		echo "unknown"
		return 1
	fi
	
	buffer_size=$(rhdwp_docker_exec "$container" "mariadb" "-u" "$db_user" "-p$db_pass" "-N" "-B" "-e" "SELECT @@innodb_buffer_pool_size;" 2>&1)
	
	# Check if we got a valid numeric value
	if [[ -n "$buffer_size" ]] && [[ "$buffer_size" =~ ^[0-9]+$ ]]; then
		# Convert bytes to MB (divide by 1024*1024)
		local mb_size=$((buffer_size / 1048576))
		echo "${mb_size}M"
	else
		echo "unknown"
		return 1
	fi
}

# Function to get current memory usage
# Args: container (string)
# Returns: memory usage in MiB via echo
get_current_memory_usage() {
	local container="$1"
	local mem_usage
	
	if ! rhdwp_docker_container_is_running "$container"; then
		echo "0"
		return 1
	fi
	
	mem_usage=$(docker stats --no-stream --format "{{.MemUsage}}" "$container" 2>/dev/null | awk -F / '{print $1}' | sed 's/[^0-9.]//g')
	
	if [[ -z "$mem_usage" ]] || [[ ! "$mem_usage" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
		echo "0"
		return 1
	fi
	
	echo "$mem_usage"
}

# Function to calculate suggested memory limit
# Args: current_mem (float), wp_scale (integer)
# Returns: suggested limit via echo
calculate_suggested_limit() {
	local current_mem="$1"
	local wp_scale="${2:-1}"
	local suggested
	
	# Use bc for floating point calculations
	suggested=$(echo "scale=2; ($current_mem * 1.5 + 255) / 256 * 256" | bc)
	# Adjust for WordPress scale
	suggested=$(echo "scale=2; $suggested * $wp_scale" | bc)
	echo "$suggested"
}

# Function to get WordPress scale
# Args: container (string)
# Returns: WordPress scale via echo
get_wordpress_scale() {
	local container="$1"
	local site_dir
	local env_file
	local wp_scale=1
	
	site_dir=$(rhdwp_docker_inspect "$container" '{{index .Config.Labels "com.docker.compose.project.working_dir"}}')
	env_file="${site_dir}/.env"
	
	if [[ -f "$env_file" ]]; then
		wp_scale=$(grep "^WORDPRESS_SCALE=" "$env_file" | cut -d= -f2 | tr -d '"' | tr -d "'" || echo "1")
		[[ -z "$wp_scale" ]] && wp_scale=1
	fi
	
	echo "$wp_scale"
}

# Function to monitor container for specified time
# Args: container (string)
# Returns: max_memory avg_memory via echo
monitor_container() {
	local container="$1"
	local max_memory=0
	local samples=0
	local total_memory=0
	local current_mem
	local i
	
	log_to_file "Monitoring $container..." "INFO"
	
	# Monitor for specified duration
	for ((i = 1; i <= SAMPLES; i++)); do
		current_mem=$(get_current_memory_usage "$container")
		if [[ "$current_mem" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
			total_memory=$(echo "$total_memory + $current_mem" | bc)
			samples=$((samples + 1))
			
			# Update max memory if current is higher
			if (($(echo "$current_mem > $max_memory" | bc -l))); then
				max_memory=$current_mem
			fi
			
			# Show progress
			if [[ "$QUIET" != true ]]; then
				printf "\rProgress: %d/%d samples" "$i" "$SAMPLES"
				printf " %-20s" "" # Clear any remaining characters
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
	[[ -z "$CONTAINER" ]] && continue
	
	((CURRENT_CONTAINER++))
	separator "="
	log_to_file "Container $CURRENT_CONTAINER of $TOTAL_CONTAINERS: $CONTAINER" "INFO"
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
		# Calculate number of samples
		SAMPLES=$(((DURATION * 60) / INTERVAL))
		# Get memory stats from monitoring
		read -r max_mem avg_mem <<<"$(monitor_container "$CONTAINER")"
	fi
	
	# Calculate suggested memory limit using bc
	suggested_limit=$(calculate_suggested_limit "$max_mem" "$wp_scale")
	
	# Calculate buffer pool size (60% of suggested limit)
	suggested_pool=$(echo "scale=0; $suggested_limit * 60 / 100" | bc)
	
	# Log results
	log_to_file "Memory Statistics for $CONTAINER:"
	if [[ "$CURRENT_ONLY" == true ]]; then
		log_to_file "  Current Usage: ${current_mem}MiB"
	else
		log_to_file "  Average Usage: ${avg_mem}MiB"
		log_to_file "  Peak Usage: ${max_mem}MiB"
	fi
	log_to_file ""
	log_to_file "Current Settings:"
	log_to_file "  Memory Limit: ${current_mem_limit}"
	log_to_file "  InnoDB Buffer Pool: ${current_buffer_pool}"
	log_to_file "  WordPress Scale: ${wp_scale}"
	log_to_file ""
	log_to_file "Recommendations:"
	log_to_file "  Suggested mem_limit: ${suggested_limit}M"
	log_to_file "  Suggested --innodb_buffer_pool_size=${suggested_pool}M"
	
	# Compare current vs suggested
	if [[ "$current_mem_limit" != "unlimited" ]] && [[ "$current_mem_limit" != "unknown" ]]; then
		current_numeric=${current_mem_limit%M}
		if (($(echo "$suggested_limit > $current_numeric" | bc -l))); then
			((summary["containers_need_increase"]++))
			log_to_file "??  Warning: Memory increase recommended" "WARN"
			log_to_file "  Current: ${current_mem_limit}"
			log_to_file "  Recommended: ${suggested_limit}M"
			log_to_file "  Difference: +$(echo "$suggested_limit - $current_numeric" | bc)M"
		elif (($(echo "$suggested_limit < $current_numeric" | bc -l))); then
			((summary["containers_can_decrease"]++))
			log_to_file "?? Note: Memory reduction possible" "INFO"
			log_to_file "  Current: ${current_mem_limit}"
			log_to_file "  Recommended: ${suggested_limit}M"
			log_to_file "  Potential savings: $(echo "$current_numeric - $suggested_limit" | bc)M"
		fi
		
		# Update summary totals
		summary["total_current_memory"]=$(echo "${summary["total_current_memory"]} + $current_numeric" | bc)
		summary["total_suggested_memory"]=$(echo "${summary["total_suggested_memory"]} + $suggested_limit" | bc)
	fi
	log_to_file ""
done < <(docker ps --filter "ancestor=mariadb" --format "{{.Names}}")

# Print summary
separator "="
log_to_file "Summary Report" "INFO"
separator "-"
log_to_file "Total Containers Analyzed: $TOTAL_CONTAINERS"
log_to_file "Containers Needing More Memory: ${summary["containers_need_increase"]}"
log_to_file "Containers That Can Reduce Memory: ${summary["containers_can_decrease"]}"
log_to_file "Total Current Memory Allocation: ${summary["total_current_memory"]}M"
log_to_file "Total Suggested Memory Allocation: ${summary["total_suggested_memory"]}M"
log_to_file "Net Memory Change: $(echo "${summary["total_suggested_memory"]} - ${summary["total_current_memory"]}" | bc)M"
separator "="

if [[ "$CURRENT_ONLY" == true ]]; then
	log_to_file "Current stats check complete. Full results saved to: $LOG_FILE" "INFO"
else
	log_to_file "Monitoring complete. Full results saved to: $LOG_FILE" "INFO"
fi

exit 0
