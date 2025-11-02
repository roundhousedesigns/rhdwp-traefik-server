#!/bin/bash
# RHDWP Mailgun API Operations
# Mailgun API wrapper functions
#
# Usage: source "$(dirname "$0")/lib/rhdwp-mailgun.sh"

# Prevent multiple sourcing
if [[ -n "${RHDWP_MAILGUN_SOURCED:-}" ]]; then
	return 0
fi
export RHDWP_MAILGUN_SOURCED=1

# Source the main library
if [[ -z "${RHDWP_LIB_SOURCED:-}" ]]; then
	# shellcheck source=/workspace/lib/rhdwp-lib.sh
	source "$(dirname "$0")/rhdwp-lib.sh" || source "/workspace/lib/rhdwp-lib.sh"
fi

# Source config library if available
if [[ -z "${RHDWP_CONFIG_SOURCED:-}" ]]; then
	# shellcheck source=/workspace/lib/rhdwp-config.sh
	source "$(dirname "$0")/rhdwp-config.sh" 2>/dev/null || true
fi

# Mailgun API endpoints
declare -r RHDWP_MG_API_BASE="https://api.mailgun.net/v3"

# Mailgun API credentials
declare -g RHDWP_MG_API_KEY="${MG_API_KEY:-}"
declare -g RHDWP_MG_DOMAIN="${MG_DOMAIN:-}"

# Make Mailgun API request
# Args: method (string), endpoint (string), data (form data, optional)
# Returns: response JSON via echo
rhdwp_mg_api_request() {
	local method="${1^^}"
	local endpoint="$2"
	local data="${3:-}"
	local url="${RHDWP_MG_API_BASE}${endpoint}"
	local curl_args=()
	local response
	local http_code
	
	# Validate credentials
	if [[ -z "$RHDWP_MG_API_KEY" ]]; then
		rhdwp_log_error "Mailgun API key not set"
		return 1
	fi
	
	# Build curl command
	curl_args=(
		-s
		-X "$method"
		--user "api:${RHDWP_MG_API_KEY}"
		-w "\n%{http_code}"
	)
	
	# Add data for POST/PUT/PATCH
	if [[ -n "$data" ]] && [[ "$method" =~ ^(POST|PUT|PATCH)$ ]]; then
		curl_args+=(-d "$data")
	fi
	
	# Add URL
	curl_args+=("$url")
	
	# Make request
	rhdwp_log_debug "Mailgun API ${method} ${endpoint}"
	
	if ! response=$(curl "${curl_args[@]}" 2>&1); then
		rhdwp_log_error "Mailgun API request failed: $response"
		return 1
	fi
	
	# Extract HTTP code (last line)
	http_code=$(echo "$response" | tail -1)
	response=$(echo "$response" | sed '$d')
	
	# Check HTTP code
	if [[ $http_code -ge 400 ]]; then
		rhdwp_log_error "Mailgun API error (HTTP $http_code): $response"
		return 1
	fi
	
	echo "$response"
	return 0
}

# Verify domain
# Args: domain (string)
# Returns: 0 on success, 1 on failure
rhdwp_mg_verify_domain() {
	local domain="$1"
	local response
	
	response=$(rhdwp_mg_api_request "GET" "/domains/${domain}") || return 1
	
	# Check if domain is verified
	if echo "$response" | jq -e '.domain.state == "active"' >/dev/null 2>&1; then
		rhdwp_log_info "Mailgun domain verified: $domain"
		return 0
	fi
	
	rhdwp_log_warn "Mailgun domain not verified: $domain"
	return 1
}

# Get domain verification records
# Args: domain (string)
# Returns: DNS records JSON via echo
rhdwp_mg_get_verification_records() {
	local domain="$1"
	local response
	
	response=$(rhdwp_mg_api_request "GET" "/domains/${domain}/verification") || return 1
	
	echo "$response" | jq -r '.receiving_dns_records, .sending_dns_records'
	return 0
}

# Initialize Mailgun API
# Args: api_key (string, optional), domain (string, optional)
# Returns: 0 on success, 1 on failure
rhdwp_init_mailgun() {
	local api_key="${1:-${MG_API_KEY:-}}"
	local domain="${2:-${MG_DOMAIN:-}}"
	
	# Check for jq
	rhdwp_require_command jq || return 1
	rhdwp_require_command curl || return 1
	
	# Set credentials
	if [[ -n "$api_key" ]]; then
		RHDWP_MG_API_KEY="$api_key"
	fi
	
	if [[ -n "$domain" ]]; then
		RHDWP_MG_DOMAIN="$domain"
	fi
	
	# Load from config if available
	if declare -f rhdwp_get_config >/dev/null; then
		if [[ -z "$RHDWP_MG_API_KEY" ]]; then
			RHDWP_MG_API_KEY=$(rhdwp_get_config "MG_API_KEY")
		fi
	fi
	
	# Validate credentials
	if [[ -z "$RHDWP_MG_API_KEY" ]]; then
		rhdwp_log_warn "Mailgun API key not set (will be required for API operations)"
		return 0
	fi
	
	rhdwp_log_debug "Mailgun API initialized"
	return 0
}
