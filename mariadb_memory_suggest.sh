#!/bin/bash

echo "Monitoring MariaDB containers for 5 minutes to determine memory usage patterns..."
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
	
	# Monitor for 5 minutes, sampling every 10 seconds
	for i in {1..30}; do
		current_mem=$(get_memory_usage "$container")
		if [[ "$current_mem" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
			total_memory=$(echo "$total_memory + $current_mem" | bc)
			samples=$((samples + 1))
			
			# Update max memory if current is higher
			if (( $(echo "$current_mem > $max_memory" | bc -l) )); then
				max_memory=$current_mem
			fi
		fi
		sleep 10
	done
	
	# Calculate average memory usage
	local avg_memory=0
	if [[ $samples -gt 0 ]]; then
		avg_memory=$(echo "scale=2; $total_memory / $samples" | bc)
	fi
	
	echo "$max_memory $avg_memory"
}

docker ps --filter "ancestor=mariadb" --format "{{.Names}}" | while read CONTAINER; do
	echo "🔍 Container: $CONTAINER"
	
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
	echo "📌 Recommendations:"
	echo "   Suggested mem_limit: ${suggested_limit}m"
	echo "   Suggested --innodb_buffer_pool_size=${suggested_pool}M"
	echo "   (Based on 1.5x peak usage, rounded to nearest 256MB)"
	echo
done
