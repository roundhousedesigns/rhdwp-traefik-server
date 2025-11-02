#!/bin/bash
# RHDWP Configuration Management
# Handles loading and validation of configuration files
#
# Usage: source "$(dirname "$0")/lib/rhdwp-config.sh"

# Prevent multiple sourcing
if [[ -n "${RHDWP_CONFIG_SOURCED:-}" ]]; then
	return 0
fi
export RHDWP_CONFIG_SOURCED=1

# Source the main library
if [[ -z "${RHDWP_LIB_SOURCED:-}" ]]; then
	# shellcheck source=/workspace/lib/rhdwp-lib.sh
	source "$(dirname "$0")/rhdwp-lib.sh" || source "/workspace/lib/rhdwp-lib.sh"
fi

# Configuration storage (associative array)
declare -A RHDWP_CONFIG

# Default configuration file paths
declare -g RHDWP_CONFIG_DIR="${RHDWP_CONFIG_DIR:-}"
declare -g RHDWP_ENV_FILE="${RHDWP_ENV_FILE:-}"

# Load environment file (.env format)
# Args: env_file (string)
# Returns: 0 on success, 1 on failure
rhdwp_load_env_file() {
	local env_file="$1"
	local line
	local key
	local value
	
	if [[ ! -f "$env_file" ]]; then
		rhdwp_log_warn "Environment file not found: $env_file"
		return 1
	fi
	
	if [[ ! -r "$env_file" ]]; then
		rhdwp_log_error "Environment file not readable: $env_file"
		return 1
	fi
	
	rhdwp_log_debug "Loading environment file: $env_file"
	
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip comments and empty lines
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		[[ -z "${line// }" ]] && continue
		
		# Parse key=value
		if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
			key="${BASH_REMATCH[1]// /}"
			value="${BASH_REMATCH[2]}"
			
			# Remove quotes if present
			value="${value#\"}"
			value="${value%\"}"
			value="${value#\'}"
			value="${value%\'}"
			
			# Store in config array
			RHDWP_CONFIG["$key"]="$value"
			export "$key=$value"
		fi
	done < "$env_file"
	
	rhdwp_log_debug "Loaded ${#RHDWP_CONFIG[@]} configuration values"
	return 0
}

# Get configuration value
# Args: key (string), default_value (string, optional)
# Returns: value via echo
rhdwp_get_config() {
	local key="$1"
	local default="${2:-}"
	
	if [[ -n "${RHDWP_CONFIG[$key]:-}" ]]; then
		echo "${RHDWP_CONFIG[$key]}"
	else
		echo "$default"
	fi
}

# Set configuration value
# Args: key (string), value (string)
rhdwp_set_config() {
	local key="$1"
	local value="$2"
	
	RHDWP_CONFIG["$key"]="$value"
	export "$key=$value"
}

# Check if configuration key exists
# Args: key (string)
# Returns: 0 if exists, 1 otherwise
rhdwp_has_config() {
	local key="$1"
	[[ -n "${RHDWP_CONFIG[$key]:-}" ]]
}

# Write configuration to .env file
# Args: env_file (string), keys... (list of keys to write, or empty for all)
# Returns: 0 on success, 1 on failure
rhdwp_write_env_file() {
	local env_file="$1"
	shift || true
	local keys=("$@")
	local key
	local temp_file
	
	# Create temp file for atomic write
	temp_file=$(rhdwp_temp_file "rhdwp-env")
	
	# If specific keys provided, write only those
	if [[ ${#keys[@]} -gt 0 ]]; then
		for key in "${keys[@]}"; do
			if [[ -n "${RHDWP_CONFIG[$key]:-}" ]]; then
				printf '%s=%s\n' "$key" "${RHDWP_CONFIG[$key]}" >> "$temp_file"
			fi
		done
	else
		# Write all config values
		for key in "${!RHDWP_CONFIG[@]}"; do
			printf '%s=%s\n' "$key" "${RHDWP_CONFIG[$key]}" >> "$temp_file"
		done
	fi
	
	# Move temp file to final location
	if [[ "$RHDWP_DRY_RUN" == "true" ]]; then
		rhdwp_log_info "[DRY RUN] Would write config to: $env_file"
		cat "$temp_file"
		rm -f "$temp_file"
	else
		mv "$temp_file" "$env_file"
		rhdwp_log_debug "Wrote configuration to: $env_file"
	fi
	
	return 0
}

# Validate required configuration keys
# Args: keys... (list of required keys)
# Returns: 0 if all present, 1 otherwise
rhdwp_validate_config() {
	local missing=()
	local key
	
	for key in "$@"; do
		if ! rhdwp_has_config "$key"; then
			missing+=("$key")
		fi
	done
	
	if [[ ${#missing[@]} -gt 0 ]]; then
		rhdwp_log_error "Missing required configuration keys: ${missing[*]}"
		return 1
	fi
	
	return 0
}

# Prompt for missing configuration values
# Args: keys... (list of keys to prompt for)
# Returns: 0 on success, 1 on failure
rhdwp_prompt_config() {
	local key
	local value
	local prompt
	local validator
	
	for key in "$@"; do
		# Skip if already set
		if rhdwp_has_config "$key"; then
			continue
		fi
		
		# Determine prompt text based on key name
		case "$key" in
			*EMAIL*|*MAIL*)
				prompt="Enter $key"
				validator="rhdwp_validate_email"
				;;
			*FQDN*|*HOST*|*DOMAIN*)
				prompt="Enter $key"
				validator="rhdwp_validate_fqdn"
				;;
			*PASSWORD*|*PASS*|*SECRET*|*KEY*|*TOKEN*)
				prompt="Enter $key"
				value=$(rhdwp_prompt_password "$prompt" false)
				rhdwp_set_config "$key" "$value"
				continue
				;;
			*)
				prompt="Enter $key"
				validator=""
				;;
		esac
		
		# Prompt for value
		if [[ -n "$validator" ]] && declare -f "$validator" >/dev/null; then
			while true; do
				value=$(rhdwp_prompt "$prompt" "" "$validator")
				if [[ -n "$value" ]]; then
					break
				fi
			done
		else
			value=$(rhdwp_prompt "$prompt")
		fi
		
		rhdwp_set_config "$key" "$value"
	done
	
	return 0
}

# Load configuration from multiple sources
# Priority: environment variables > .env file > defaults
# Args: config_dir (string, optional), env_file (string, optional)
# Returns: 0 on success, 1 on failure
rhdwp_load_config() {
	local config_dir="${1:-${RHDWP_CONFIG_DIR:-}}"
	local env_file="${2:-${RHDWP_ENV_FILE:-}}"
	
	# Determine config file location
	if [[ -z "$env_file" ]]; then
		if [[ -n "$config_dir" ]] && [[ -f "$config_dir/.env" ]]; then
			env_file="$config_dir/.env"
		elif [[ -f "$(rhdwp_project_root)/traefik/.env" ]]; then
			env_file="$(rhdwp_project_root)/traefik/.env"
		fi
	fi
	
	# Load from file if exists
	if [[ -n "$env_file" ]] && [[ -f "$env_file" ]]; then
		rhdwp_load_env_file "$env_file" || return 1
	fi
	
	# Override with environment variables (if set)
	for key in "${!RHDWP_CONFIG[@]}"; do
		if [[ -n "${!key:-}" ]]; then
			RHDWP_CONFIG["$key"]="${!key}"
		fi
	done
	
	rhdwp_log_debug "Configuration loaded with ${#RHDWP_CONFIG[@]} values"
	return 0
}

# Initialize configuration system
# Args: config_dir (string, optional), env_file (string, optional)
rhdwp_init_config() {
	local config_dir="${1:-}"
	local env_file="${2:-}"
	
	RHDWP_CONFIG_DIR="$config_dir"
	RHDWP_ENV_FILE="$env_file"
	
	rhdwp_load_config "$config_dir" "$env_file"
}
