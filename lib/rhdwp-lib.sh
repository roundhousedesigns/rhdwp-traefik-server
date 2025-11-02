#!/bin/bash
# RHDWP Shared Library
# Common functions for all RHDWP scripts
#
# Usage: source "$(dirname "$0")/lib/rhdwp-lib.sh" or source "/path/to/lib/rhdwp-lib.sh"

# Prevent multiple sourcing
if [[ -n "${RHDWP_LIB_SOURCED:-}" ]]; then
	return 0
fi
export RHDWP_LIB_SOURCED=1

# Default strict mode settings
# Scripts should call rhdwp_setup_error_handling() or set their own strict mode
# Don't set strict mode here as it may interfere with library sourcing

# Global variables
declare -g RHDWP_LOG_LEVEL="${RHDWP_LOG_LEVEL:-INFO}"
declare -g RHDWP_VERBOSE="${RHDWP_VERBOSE:-false}"
declare -g RHDWP_DEBUG="${RHDWP_DEBUG:-false}"
declare -g RHDWP_DRY_RUN="${RHDWP_DRY_RUN:-false}"

# Log levels (numeric for comparison)
declare -A RHDWP_LOG_LEVELS=(
	[DEBUG]=0
	[INFO]=1
	[WARN]=2
	[ERROR]=3
	[FATAL]=4
)

# Color codes for output
declare -A RHDWP_COLORS=(
	[DEBUG]='\033[0;36m'  # Cyan
	[INFO]='\033[0;32m'   # Green
	[WARN]='\033[1;33m'   # Yellow
	[ERROR]='\033[1;31m'  # Red
	[FATAL]='\033[1;35m'  # Magenta
	[RESET]='\033[0m'     # Reset
)

# Get numeric log level
# Args: log_level (string)
# Returns: numeric level (integer)
_rhdwp_get_log_level() {
	local level="${1:-INFO}"
	level="${level^^}"
	echo "${RHDWP_LOG_LEVELS[$level]:-1}"
}

# Check if log level should be shown
# Args: message_level (string)
# Returns: 0 if should show, 1 otherwise
_rhdwp_should_log() {
	local msg_level="${1:-INFO}"
	local current_level
	local msg_level_num
	
	current_level=$(_rhdwp_get_log_level "$RHDWP_LOG_LEVEL")
	msg_level_num=$(_rhdwp_get_log_level "$msg_level")
	
	[[ $msg_level_num -ge $current_level ]]
}

# Log a message
# Args: level (string), message (string), ... (additional args for printf)
rhdwp_log() {
	local level="${1:-INFO}"
	local message="${2:-}"
	shift 2 || true
	local formatted_msg
	
	# Format message with additional arguments if provided
	if [[ $# -gt 0 ]]; then
		formatted_msg=$(printf "$message" "$@")
	else
		formatted_msg="$message"
	fi
	
	# Check if we should log this level
	if ! _rhdwp_should_log "$level"; then
		return 0
	fi
	
	# Color output if terminal supports it
	local color="${RHDWP_COLORS[$level]:-${RHDWP_COLORS[INFO]}}"
	local reset="${RHDWP_COLORS[RESET]}"
	local timestamp
	
	if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
		timestamp=$(date '+%Y-%m-%d %H:%M:%S')
		printf '%b[%s] %s: %s%b\n' "$color" "$timestamp" "$level" "$formatted_msg" "$reset" >&2
	else
		timestamp=$(date '+%Y-%m-%d %H:%M:%S')
		printf '[%s] %s: %s\n' "$timestamp" "$level" "$formatted_msg" >&2
	fi
}

# Convenience functions for different log levels
rhdwp_log_debug() { rhdwp_log "DEBUG" "$@"; }
rhdwp_log_info() { rhdwp_log "INFO" "$@"; }
rhdwp_log_warn() { rhdwp_log "WARN" "$@"; }
rhdwp_log_error() { rhdwp_log "ERROR" "$@"; }
rhdwp_log_fatal() { rhdwp_log "FATAL" "$@"; }

# Error handler with cleanup support
# Args: line_number (integer), command (string), exit_code (integer)
_rhdwp_error_handler() {
	local line_num="${1:-unknown}"
	local command="${2:-unknown}"
	local exit_code="${3:-1}"
	
	# Call cleanup function if it exists
	if declare -f rhdwp_cleanup >/dev/null; then
		rhdwp_cleanup || true
	fi
	
	rhdwp_log_error "Error at line $line_num: command '$command' exited with code $exit_code"
	exit "$exit_code"
}

# Set up error handling
# Args: enable (true/false, default: true)
rhdwp_setup_error_handling() {
	local enable="${1:-true}"
	
	if [[ "$enable" == "true" ]]; then
		set -euo pipefail
		trap '_rhdwp_error_handler ${LINENO} "${BASH_COMMAND}" $?' ERR
	else
		set +e
		trap - ERR
	fi
}

# Cleanup function placeholder
# Override this in scripts that need cleanup
rhdwp_cleanup() {
	:
}

# Trap for cleanup on exit
trap 'rhdwp_cleanup' EXIT INT TERM

# Validate that a command exists
# Args: command_name (string)
# Returns: 0 if exists, 1 otherwise
rhdwp_require_command() {
	local cmd="$1"
	
	if ! command -v "$cmd" >/dev/null 2>&1; then
		rhdwp_log_error "Required command not found: $cmd"
		return 1
	fi
	return 0
}

# Validate multiple commands exist
# Args: command1 command2 ... (string list)
# Returns: 0 if all exist, 1 otherwise
rhdwp_require_commands() {
	local missing=()
	local cmd
	
	for cmd in "$@"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing+=("$cmd")
		fi
	done
	
	if [[ ${#missing[@]} -gt 0 ]]; then
		rhdwp_log_error "Missing required commands: ${missing[*]}"
		return 1
	fi
	return 0
}

# Validate file exists and is readable
# Args: file_path (string)
# Returns: 0 if exists and readable, 1 otherwise
rhdwp_require_file() {
	local file="$1"
	
	if [[ ! -f "$file" ]]; then
		rhdwp_log_error "Required file not found: $file"
		return 1
	fi
	
	if [[ ! -r "$file" ]]; then
		rhdwp_log_error "File not readable: $file"
		return 1
	fi
	
	return 0
}

# Validate directory exists and is accessible
# Args: dir_path (string)
# Returns: 0 if exists and accessible, 1 otherwise
rhdwp_require_directory() {
	local dir="$1"
	
	if [[ ! -d "$dir" ]]; then
		rhdwp_log_error "Required directory not found: $dir"
		return 1
	fi
	
	if [[ ! -r "$dir" ]]; then
		rhdwp_log_error "Directory not accessible: $dir"
		return 1
	fi
	
	return 0
}

# Sanitize a string for use in filenames
# Args: string (string)
# Returns: sanitized string
rhdwp_sanitize_filename() {
	local str="$1"
	# Remove or replace dangerous characters
	echo "$str" | tr -dc '[:alnum:]._-' | tr '[:upper:]' '[:lower:]'
}

# Sanitize a string for use in shell commands
# Args: string (string)
# Returns: sanitized string (quoted)
rhdwp_sanitize_shell() {
	local str="$1"
	# Use printf %q to safely quote
	printf '%q' "$str"
}

# Validate FQDN format
# Args: fqdn (string)
# Returns: 0 if valid, 1 otherwise
rhdwp_validate_fqdn() {
	local fqdn="$1"
	
	# Basic FQDN regex: valid domain name
	if [[ ! "$fqdn" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
		rhdwp_log_error "Invalid FQDN format: $fqdn"
		return 1
	fi
	
	return 0
}

# Validate email format
# Args: email (string)
# Returns: 0 if valid, 1 otherwise
rhdwp_validate_email() {
	local email="$1"
	
	# Basic email regex
	if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
		rhdwp_log_error "Invalid email format: $email"
		return 1
	fi
	
	return 0
}

# Prompt for input with validation
# Args: prompt (string), default_value (string, optional), validator (function name, optional)
# Returns: user input via echo
rhdwp_prompt() {
	local prompt="$1"
	local default="${2:-}"
	local validator="${3:-}"
	local value
	local prompt_text
	
	if [[ -n "$default" ]]; then
		prompt_text="$prompt [$default]: "
	else
		prompt_text="$prompt: "
	fi
	
	while true; do
		read -r -p "$prompt_text" value
		
		# Use default if empty
		if [[ -z "$value" && -n "$default" ]]; then
			value="$default"
		fi
		
		# Skip validation if empty and no default
		if [[ -z "$value" ]]; then
			rhdwp_log_warn "Input cannot be empty"
			continue
		fi
		
		# Run validator if provided
		if [[ -n "$validator" ]] && declare -f "$validator" >/dev/null; then
			if "$validator" "$value"; then
				echo "$value"
				return 0
			else
				continue
			fi
		else
			echo "$value"
			return 0
		fi
	done
}

# Prompt for password (hidden input)
# Args: prompt (string), confirm (boolean, default: false)
# Returns: password via echo
rhdwp_prompt_password() {
	local prompt="$1"
	local confirm="${2:-false}"
	local password
	local password_confirm
	
	while true; do
		read -rs -p "$prompt: " password
		echo >&2
		
		if [[ -z "$password" ]]; then
			rhdwp_log_warn "Password cannot be empty"
			continue
		fi
		
		if [[ "$confirm" == "true" ]]; then
			read -rs -p "Confirm password: " password_confirm
			echo >&2
			
			if [[ "$password" != "$password_confirm" ]]; then
				rhdwp_log_error "Passwords do not match"
				continue
			fi
		fi
		
		echo "$password"
		return 0
	done
}

# Run command with dry-run support
# Args: command (string), ... (additional args)
# Returns: command exit code
rhdwp_run() {
	local cmd="$1"
	shift || true
	
	if [[ "$RHDWP_DRY_RUN" == "true" ]]; then
		rhdwp_log_info "[DRY RUN] Would execute: $cmd $*"
		return 0
	else
		if [[ "$RHDWP_VERBOSE" == "true" ]] || [[ "$RHDWP_DEBUG" == "true" ]]; then
			rhdwp_log_debug "Executing: $cmd $*"
		fi
		"$cmd" "$@"
	fi
}

# Create temporary file safely
# Args: prefix (string, optional)
# Returns: temp file path via echo
rhdwp_temp_file() {
	local prefix="${1:-rhdwp}"
	mktemp "/tmp/${prefix}.XXXXXX"
}

# Create temporary directory safely
# Args: prefix (string, optional)
# Returns: temp directory path via echo
rhdwp_temp_dir() {
	local prefix="${1:-rhdwp}"
	mktemp -d "/tmp/${prefix}.XXXXXX"
}

# Check if running as root
# Returns: 0 if root, 1 otherwise
rhdwp_is_root() {
	[[ $EUID -eq 0 ]]
}

# Check if running as specific user
# Args: username (string)
# Returns: 0 if running as user, 1 otherwise
rhdwp_is_user() {
	local username="$1"
	[[ "$(whoami)" == "$username" ]]
}

# Get script directory (resolves symlinks)
# Returns: directory path via echo
rhdwp_script_dir() {
	local script_path
	script_path="$(readlink -f "${BASH_SOURCE[1]:-$0}")"
	dirname "$script_path"
}

# Get script root directory (project root)
# Returns: root directory path via echo
rhdwp_project_root() {
	local script_dir
	script_dir=$(rhdwp_script_dir)
	
	# Look for marker files to identify project root
	local current="$script_dir"
	while [[ "$current" != "/" ]]; do
		if [[ -f "$current/rhdwpTraefik" ]] || [[ -d "$current/traefik" ]]; then
			echo "$current"
			return 0
		fi
		current=$(dirname "$current")
	done
	
	# Fallback to script directory
	echo "$script_dir"
}

# Check if bash version is >= 4.0
# Returns: 0 if >= 4.0, 1 otherwise
rhdwp_check_bash_version() {
	local major_version
	major_version="${BASH_VERSION%%.*}"
	
	if [[ $major_version -lt 4 ]]; then
		rhdwp_log_error "Bash 4.0 or higher required. Current version: $BASH_VERSION"
		return 1
	fi
	
	return 0
}

# Initialize library (call this in scripts)
# Args: script_name (string)
rhdwp_init() {
	local script_name="${1:-unknown}"
	
	# Check bash version
	rhdwp_check_bash_version || exit 1
	
	# Set up error handling
	rhdwp_setup_error_handling
	
	rhdwp_log_debug "Initialized RHDWP library for script: $script_name"
}

# Set log level
# Args: level (string: DEBUG, INFO, WARN, ERROR, FATAL)
rhdwp_set_log_level() {
	local level="${1:-INFO}"
	level="${level^^}"
	
	if [[ -z "${RHDWP_LOG_LEVELS[$level]:-}" ]]; then
		rhdwp_log_error "Invalid log level: $level. Valid levels: ${!RHDWP_LOG_LEVELS[*]}"
		return 1
	fi
	
	RHDWP_LOG_LEVEL="$level"
	rhdwp_log_info "Log level set to: $level"
}

# Enable verbose mode
rhdwp_enable_verbose() {
	RHDWP_VERBOSE=true
	RHDWP_DEBUG=true
	rhdwp_set_log_level "DEBUG"
}

# Enable debug mode
rhdwp_enable_debug() {
	RHDWP_DEBUG=true
	rhdwp_set_log_level "DEBUG"
}

# Enable dry-run mode
rhdwp_enable_dry_run() {
	RHDWP_DRY_RUN=true
	rhdwp_log_info "Dry-run mode enabled"
}
