#!/bin/bash
# RHDWP Cron Replacement
# Replacement for WordPress wp-cron.php
# Triggers WordPress cron jobs for all sites via HTTP requests
#
# Usage: ./rhdwpCron.sh [options]
# Options:
#   -d <dir>   Site directory (default: /srv/rhdwp/www)
#   -t <sec>   Timeout in seconds (default: 30)
#   -q         Quiet mode
#   -v         Verbose mode
#   -h         Show help

# Source the main library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/rhdwp-lib.sh" || source "/workspace/lib/rhdwp-lib.sh"
source "${SCRIPT_DIR}/rhdwp-docker.sh" 2>/dev/null || source "/workspace/lib/rhdwp-docker.sh"

# Default values
WWW_DIR="${WWW_DIR:-/srv/rhdwp/www}"
TIMEOUT="${TIMEOUT:-30}"
QUIET_MODE=false
VERBOSE_MODE=false

# Help function
show_help() {
	echo "RHDWP Cron Replacement"
	echo "======================="
	echo "Triggers WordPress cron jobs for all sites"
	echo
	echo "Usage: $0 [options]"
	echo
	echo "Options:"
	echo "  -d <dir>   Site directory (default: /srv/rhdwp/www)"
	echo "  -t <sec>   Timeout in seconds (default: 30)"
	echo "  -q         Quiet mode"
	echo "  -v         Verbose mode"
	echo "  -h         Show help"
	exit 0
}

# Parse command line arguments
while getopts "d:t:qvh" opt; do
	case $opt in
		d)
			WWW_DIR="$OPTARG"
			;;
		t)
			TIMEOUT="$OPTARG"
			;;
		q)
			QUIET_MODE=true
			;;
		v)
			VERBOSE_MODE=true
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
if [[ ! -d "$WWW_DIR" ]]; then
	rhdwp_log_error "Site directory not found: $WWW_DIR"
	exit 1
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -lt 1 ]]; then
	rhdwp_log_error "Timeout must be a positive integer"
	exit 1
fi

# Initialize
rhdwp_init "rhdwpCron"

# Check if wget is available
rhdwp_require_command wget || exit 1

# Function to check if site stack is running
# Args: site_dir (string)
# Returns: 0 if running, 1 otherwise
is_site_running() {
	local site_dir="$1"
	local site_name
	local project_name
	
	# Extract site name from directory
	site_name=$(basename "$site_dir")
	
	# Try to find project name from docker-compose.yml
	if [[ -f "$site_dir/docker-compose.yml" ]]; then
		project_name=$(grep -E "^[[:space:]]*project_name:" "$site_dir/docker-compose.yml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "")
	fi
	
	# If no project name, use directory name
	project_name="${project_name:-$site_name}"
	
	# Check if any containers are running for this project
	if declare -f rhdwp_docker_project_has_running >/dev/null; then
		rhdwp_docker_project_has_running "$project_name" 2>/dev/null
	else
		# Fallback: check if docker-compose shows running containers
		if [[ -f "$site_dir/docker-compose.yml" ]]; then
			(cd "$site_dir" && docker compose ps --format json 2>/dev/null | jq -e '.[] | select(.State == "running")' >/dev/null 2>&1)
		else
			# Assume running if we can't check
			return 0
		fi
	fi
}

# Function to trigger WordPress cron
# Args: site_url (string)
# Returns: 0 on success, 1 on failure
trigger_wp_cron() {
	local site_url="$1"
	local cron_url="${site_url}/wp-cron.php?doing_wp_cron"
	local response
	local exit_code
	
	if [[ "$VERBOSE_MODE" == "true" ]]; then
		rhdwp_log_debug "Triggering cron for: $site_url"
	fi
	
	# Use wget with timeout
	if response=$(wget -q --timeout="$TIMEOUT" --tries=1 -O - "$cron_url" 2>&1); then
		if [[ "$VERBOSE_MODE" == "true" ]]; then
			rhdwp_log_debug "Cron triggered successfully for: $site_url"
		fi
		return 0
	else
		if [[ "$QUIET_MODE" != "true" ]]; then
			rhdwp_log_warn "Failed to trigger cron for $site_url: $response"
		fi
		return 1
	fi
}

# Main execution
if [[ "$QUIET_MODE" != "true" ]]; then
	rhdwp_log_info "Starting WordPress cron triggers for sites in: $WWW_DIR"
fi

success_count=0
fail_count=0

# Process each site directory
for site_dir in "$WWW_DIR"/*; do
	# Skip if not a directory
	[[ ! -d "$site_dir" ]] && continue
	
	site_name=$(basename "$site_dir")
	
	# Skip hidden directories
	[[ "$site_name" =~ ^\. ]] && continue
	
	# Check if site stack is running
	if ! is_site_running "$site_dir"; then
		if [[ "$VERBOSE_MODE" == "true" ]]; then
			rhdwp_log_debug "Skipping $site_name: site stack not running"
		fi
		continue
	fi
	
	# Construct site URL (assuming site name is the domain)
	site_url="https://${site_name}"
	
	# Trigger cron
	if trigger_wp_cron "$site_url"; then
		((success_count++))
	else
		((fail_count++))
	fi
done

# Summary
if [[ "$QUIET_MODE" != "true" ]]; then
	rhdwp_log_info "Cron trigger complete: $success_count successful, $fail_count failed"
fi

exit $((fail_count > 0 ? 1 : 0))
