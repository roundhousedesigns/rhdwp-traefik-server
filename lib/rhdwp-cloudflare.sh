#!/bin/bash
# RHDWP CloudFlare API Operations
# CloudFlare DNS and API wrapper functions
#
# Usage: source "$(dirname "$0")/lib/rhdwp-cloudflare.sh"

# Prevent multiple sourcing
if [[ -n "${RHDWP_CLOUDFLARE_SOURCED:-}" ]]; then
	return 0
fi
export RHDWP_CLOUDFLARE_SOURCED=1

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

# CloudFlare API endpoints
declare -r RHDWP_CF_API_BASE="https://api.cloudflare.com/client/v4"

# CloudFlare API credentials
declare -g RHDWP_CF_API_EMAIL="${CF_API_EMAIL:-}"
declare -g RHDWP_CF_API_KEY="${CF_API_KEY:-}"

# Make CloudFlare API request
# Args: method (string), endpoint (string), data (JSON string, optional)
# Returns: response JSON via echo
rhdwp_cf_api_request() {
	local method="${1^^}"
	local endpoint="$2"
	local data="${3:-}"
	local url="${RHDWP_CF_API_BASE}${endpoint}"
	local curl_args=()
	local response
	local http_code
	
	# Validate credentials
	if [[ -z "$RHDWP_CF_API_EMAIL" ]] || [[ -z "$RHDWP_CF_API_KEY" ]]; then
		rhdwp_log_error "CloudFlare API credentials not set"
		return 1
	fi
	
	# Build curl command
	curl_args=(
		-s
		-X "$method"
		-H "X-Auth-Email: ${RHDWP_CF_API_EMAIL}"
		-H "X-Auth-Key: ${RHDWP_CF_API_KEY}"
		-H "Content-Type: application/json"
		-w "\n%{http_code}"
	)
	
	# Add data for POST/PUT/PATCH
	if [[ -n "$data" ]] && [[ "$method" =~ ^(POST|PUT|PATCH)$ ]]; then
		curl_args+=(-d "$data")
	fi
	
	# Add URL
	curl_args+=("$url")
	
	# Make request
	rhdwp_log_debug "CloudFlare API ${method} ${endpoint}"
	
	if ! response=$(curl "${curl_args[@]}" 2>&1); then
		rhdwp_log_error "CloudFlare API request failed: $response"
		return 1
	fi
	
	# Extract HTTP code (last line)
	http_code=$(echo "$response" | tail -1)
	response=$(echo "$response" | sed '$d')
	
	# Check HTTP code
	if [[ $http_code -ge 400 ]]; then
		rhdwp_log_error "CloudFlare API error (HTTP $http_code): $response"
		return 1
	fi
	
	# Check API success
	if ! echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
		local errors
		errors=$(echo "$response" | jq -r '.errors[]?.message // "Unknown error"' 2>/dev/null || echo "Unknown error")
		rhdwp_log_error "CloudFlare API returned errors: $errors"
		return 1
	fi
	
	echo "$response"
	return 0
}

# Get zone ID by domain name
# Args: domain (string)
# Returns: zone_id via echo
rhdwp_cf_get_zone_id() {
	local domain="$1"
	local response
	local zone_id
	
	response=$(rhdwp_cf_api_request "GET" "/zones?name=${domain}&status=active&match=all") || return 1
	
	zone_id=$(echo "$response" | jq -r '.result[0].id // empty')
	
	if [[ -z "$zone_id" ]] || [[ "$zone_id" == "null" ]]; then
		rhdwp_log_error "Zone not found for domain: $domain"
		return 1
	fi
	
	echo "$zone_id"
	return 0
}

# Get DNS record
# Args: zone_id (string), record_type (string), name (string)
# Returns: record JSON via echo
rhdwp_cf_get_dns_record() {
	local zone_id="$1"
	local record_type="$2"
	local name="$3"
	local response
	local record
	
	response=$(rhdwp_cf_api_request "GET" "/zones/${zone_id}/dns_records?type=${record_type}&name=${name}") || return 1
	
	record=$(echo "$response" | jq -r '.result[0] // empty')
	
	if [[ -z "$record" ]] || [[ "$record" == "null" ]]; then
		return 1
	fi
	
	echo "$record"
	return 0
}

# Create DNS record
# Args: zone_id (string), record_type (string), name (string), content (string), ttl (integer, default: 1), proxied (boolean, default: false)
# Returns: record JSON via echo
rhdwp_cf_create_dns_record() {
	local zone_id="$1"
	local record_type="$2"
	local name="$3"
	local content="$4"
	local ttl="${5:-1}"
	local proxied="${6:-false}"
	local data
	local response
	
	# Build JSON payload
	data=$(jq -n \
		--arg type "$record_type" \
		--arg name "$name" \
		--arg content "$content" \
		--argjson ttl "$ttl" \
		--argjson proxied "$proxied" \
		'{type: $type, name: $name, content: $content, ttl: $ttl, proxied: $proxied}')
	
	response=$(rhdwp_cf_api_request "POST" "/zones/${zone_id}/dns_records" "$data") || return 1
	
	echo "$response" | jq -r '.result'
	return 0
}

# Update DNS record
# Args: zone_id (string), record_id (string), record_type (string), name (string), content (string), ttl (integer, default: 1), proxied (boolean, default: false)
# Returns: record JSON via echo
rhdwp_cf_update_dns_record() {
	local zone_id="$1"
	local record_id="$2"
	local record_type="$3"
	local name="$4"
	local content="$5"
	local ttl="${6:-1}"
	local proxied="${7:-false}"
	local data
	local response
	
	# Build JSON payload
	data=$(jq -n \
		--arg type "$record_type" \
		--arg name "$name" \
		--arg content "$content" \
		--argjson ttl "$ttl" \
		--argjson proxied "$proxied" \
		'{type: $type, name: $name, content: $content, ttl: $ttl, proxied: $proxied}')
	
	response=$(rhdwp_cf_api_request "PUT" "/zones/${zone_id}/dns_records/${record_id}" "$data") || return 1
	
	echo "$response" | jq -r '.result'
	return 0
}

# Delete DNS record
# Args: zone_id (string), record_id (string)
# Returns: 0 on success, 1 on failure
rhdwp_cf_delete_dns_record() {
	local zone_id="$1"
	local record_id="$2"
	
	rhdwp_cf_api_request "DELETE" "/zones/${zone_id}/dns_records/${record_id}" >/dev/null || return 1
	
	rhdwp_log_info "Deleted DNS record: $record_id"
	return 0
}

# Ensure CNAME record exists (create or update)
# Args: zone_id (string), name (string), content (string), ttl (integer, default: 1), proxied (boolean, default: false)
# Returns: 0 on success, 1 on failure
rhdwp_cf_ensure_cname() {
	local zone_id="$1"
	local name="$2"
	local content="$3"
	local ttl="${4:-1}"
	local proxied="${5:-false}"
	local existing_record
	local record_id
	
	# Check if record exists
	if existing_record=$(rhdwp_cf_get_dns_record "$zone_id" "CNAME" "$name"); then
		record_id=$(echo "$existing_record" | jq -r '.id')
		rhdwp_log_debug "CNAME record exists, updating: $name"
		rhdwp_cf_update_dns_record "$zone_id" "$record_id" "CNAME" "$name" "$content" "$ttl" "$proxied" >/dev/null || return 1
	else
		rhdwp_log_debug "Creating CNAME record: $name"
		rhdwp_cf_create_dns_record "$zone_id" "CNAME" "$name" "$content" "$ttl" "$proxied" >/dev/null || return 1
	fi
	
	return 0
}

# Create multiple CNAME records
# Args: zone_id (string), base_domain (string), records... (array of subdomain names)
# Returns: 0 on success, 1 on failure
rhdwp_cf_create_cnames() {
	local zone_id="$1"
	local base_domain="$2"
	shift 2 || true
	local records=("$@")
	local record
	local name
	local content
	
	for record in "${records[@]}"; do
		# Build full name (subdomain.base_domain)
		name="${record}.${base_domain}"
		content="$base_domain"
		
		rhdwp_log_info "Ensuring CNAME: $name -> $content"
		rhdwp_cf_ensure_cname "$zone_id" "$name" "$content" "1" "false" || return 1
	done
	
	return 0
}

# Extract TLD from FQDN
# Args: fqdn (string)
# Returns: TLD via echo
rhdwp_cf_extract_tld() {
	local fqdn="$1"
	echo "$fqdn" | grep -o '[^.]*\.[^.]*$' || echo "$fqdn"
}

# Initialize CloudFlare API
# Args: api_email (string, optional), api_key (string, optional)
# Returns: 0 on success, 1 on failure
rhdwp_init_cloudflare() {
	local api_email="${1:-${CF_API_EMAIL:-}}"
	local api_key="${2:-${CF_API_KEY:-}}"
	
	# Check for jq
	rhdwp_require_command jq || return 1
	rhdwp_require_command curl || return 1
	
	# Set credentials
	if [[ -n "$api_email" ]]; then
		RHDWP_CF_API_EMAIL="$api_email"
	fi
	
	if [[ -n "$api_key" ]]; then
		RHDWP_CF_API_KEY="$api_key"
	fi
	
	# Load from config if available
	if declare -f rhdwp_get_config >/dev/null; then
		if [[ -z "$RHDWP_CF_API_EMAIL" ]]; then
			RHDWP_CF_API_EMAIL=$(rhdwp_get_config "CF_API_EMAIL")
		fi
		if [[ -z "$RHDWP_CF_API_KEY" ]]; then
			RHDWP_CF_API_KEY=$(rhdwp_get_config "CF_API_KEY")
		fi
	fi
	
	# Validate credentials
	if [[ -z "$RHDWP_CF_API_EMAIL" ]] || [[ -z "$RHDWP_CF_API_KEY" ]]; then
		rhdwp_log_warn "CloudFlare API credentials not set (will be required for API operations)"
		return 0
	fi
	
	rhdwp_log_debug "CloudFlare API initialized"
	return 0
}
