#!/bin/bash
# RHDWP Docker Operations
# Docker and docker-compose wrapper functions
#
# Usage: source "$(dirname "$0")/lib/rhdwp-docker.sh"

# Prevent multiple sourcing
if [[ -n "${RHDWP_DOCKER_SOURCED:-}" ]]; then
	return 0
fi
export RHDWP_DOCKER_SOURCED=1

# Source the main library
if [[ -z "${RHDWP_LIB_SOURCED:-}" ]]; then
	# shellcheck source=/workspace/lib/rhdwp-lib.sh
	source "$(dirname "$0")/rhdwp-lib.sh" || source "/workspace/lib/rhdwp-lib.sh"
fi

# Docker compose command (prefer plugin, fallback to standalone)
declare -g RHDWP_DOCKER_COMPOSE_CMD=""

# Detect docker compose command
_rhdwp_detect_docker_compose() {
	if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
		RHDWP_DOCKER_COMPOSE_CMD="docker compose"
		rhdwp_log_debug "Using docker compose plugin"
	elif command -v docker-compose >/dev/null 2>&1; then
		RHDWP_DOCKER_COMPOSE_CMD="docker-compose"
		rhdwp_log_debug "Using docker-compose standalone"
	else
		rhdwp_log_error "Neither 'docker compose' nor 'docker-compose' found"
		return 1
	fi
	return 0
}

# Initialize docker compose command detection
_rhdwp_detect_docker_compose

# Check if Docker is running
# Returns: 0 if running, 1 otherwise
rhdwp_docker_is_running() {
	if ! docker info >/dev/null 2>&1; then
		rhdwp_log_error "Docker daemon is not running"
		return 1
	fi
	return 0
}

# Check if container exists
# Args: container_name (string)
# Returns: 0 if exists, 1 otherwise
rhdwp_docker_container_exists() {
	local container="$1"
	docker ps -a --format '{{.Names}}' | grep -q "^${container}$" 2>/dev/null
}

# Check if container is running
# Args: container_name (string)
# Returns: 0 if running, 1 otherwise
rhdwp_docker_container_is_running() {
	local container="$1"
	docker ps --format '{{.Names}}' | grep -q "^${container}$" 2>/dev/null
}

# Get container status
# Args: container_name (string)
# Returns: status string via echo
rhdwp_docker_container_status() {
	local container="$1"
	docker ps -a --filter "name=^${container}$" --format '{{.Status}}' 2>/dev/null || echo "not found"
}

# Wait for container to be healthy
# Args: container_name (string), timeout (integer, seconds, default: 60)
# Returns: 0 if healthy, 1 on timeout
rhdwp_docker_wait_healthy() {
	local container="$1"
	local timeout="${2:-60}"
	local elapsed=0
	local status
	
	rhdwp_log_debug "Waiting for container $container to be healthy (timeout: ${timeout}s)"
	
	while [[ $elapsed -lt $timeout ]]; do
		status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
		
		if [[ "$status" == "healthy" ]]; then
			rhdwp_log_debug "Container $container is healthy"
			return 0
		fi
		
		sleep 1
		((elapsed++))
	done
	
	rhdwp_log_warn "Container $container did not become healthy within ${timeout}s"
	return 1
}

# Check if network exists
# Args: network_name (string)
# Returns: 0 if exists, 1 otherwise
rhdwp_docker_network_exists() {
	local network="$1"
	docker network ls --format '{{.Name}}' | grep -q "^${network}$" 2>/dev/null
}

# Create network if it doesn't exist
# Args: network_name (string)
# Returns: 0 on success, 1 on failure
rhdwp_docker_network_create() {
	local network="$1"
	
	if rhdwp_docker_network_exists "$network"; then
		rhdwp_log_debug "Network $network already exists"
		return 0
	fi
	
	rhdwp_log_info "Creating Docker network: $network"
	rhdwp_run docker network create "$network" || return 1
	return 0
}

# Docker compose wrapper
# Args: compose_dir (string), command (string), ... (additional args)
# Returns: command exit code
rhdwp_docker_compose() {
	local compose_dir="$1"
	local command="$2"
	shift 2 || true
	
	local cmd
	
	# Build command string
	if [[ "$RHDWP_DOCKER_COMPOSE_CMD" == "docker compose" ]]; then
		cmd="docker compose -f \"$compose_dir/docker-compose.yml\""
	else
		cmd="docker-compose -f \"$compose_dir/docker-compose.yml\""
	fi
	
	# Add project directory if using docker compose plugin
	if [[ "$RHDWP_DOCKER_COMPOSE_CMD" == "docker compose" ]]; then
		cmd="$cmd --project-directory \"$compose_dir\""
	fi
	
	# Execute command
	rhdwp_log_debug "Running docker compose: $command in $compose_dir"
	
	if [[ "$RHDWP_DRY_RUN" == "true" ]]; then
		rhdwp_log_info "[DRY RUN] Would execute: $cmd $command $*"
		return 0
	fi
	
	# Change to directory and run command
	(cd "$compose_dir" && eval "$cmd $command $*")
}

# Docker compose up
# Args: compose_dir (string), ... (additional docker compose args)
# Returns: command exit code
rhdwp_docker_compose_up() {
	local compose_dir="$1"
	shift || true
	rhdwp_docker_compose "$compose_dir" "up" "$@"
}

# Docker compose down
# Args: compose_dir (string), ... (additional docker compose args)
# Returns: command exit code
rhdwp_docker_compose_down() {
	local compose_dir="$1"
	shift || true
	rhdwp_docker_compose "$compose_dir" "down" "$@"
}

# Docker compose pull
# Args: compose_dir (string), ... (additional docker compose args)
# Returns: command exit code
rhdwp_docker_compose_pull() {
	local compose_dir="$1"
	shift || true
	rhdwp_docker_compose "$compose_dir" "pull" "$@"
}

# Docker compose restart
# Args: compose_dir (string), ... (additional docker compose args)
# Returns: command exit code
rhdwp_docker_compose_restart() {
	local compose_dir="$1"
	shift || true
	rhdwp_docker_compose "$compose_dir" "restart" "$@"
}

# Docker compose ps
# Args: compose_dir (string), ... (additional docker compose args)
# Returns: command exit code
rhdwp_docker_compose_ps() {
	local compose_dir="$1"
	shift || true
	rhdwp_docker_compose "$compose_dir" "ps" "$@"
}

# Docker compose logs
# Args: compose_dir (string), ... (additional docker compose args)
# Returns: command exit code
rhdwp_docker_compose_logs() {
	local compose_dir="$1"
	shift || true
	rhdwp_docker_compose "$compose_dir" "logs" "$@"
}

# Get container logs
# Args: container_name (string), lines (integer, default: 100)
# Returns: logs via echo
rhdwp_docker_logs() {
	local container="$1"
	local lines="${2:-100}"
	
	if ! rhdwp_docker_container_exists "$container"; then
		rhdwp_log_error "Container not found: $container"
		return 1
	fi
	
	docker logs --tail "$lines" "$container" 2>&1
}

# Execute command in container
# Args: container_name (string), command (string), ... (additional args)
# Returns: command exit code
rhdwp_docker_exec() {
	local container="$1"
	local command="$2"
	shift 2 || true
	
	if ! rhdwp_docker_container_is_running "$container"; then
		rhdwp_log_error "Container is not running: $container"
		return 1
	fi
	
	rhdwp_log_debug "Executing in container $container: $command $*"
	rhdwp_run docker exec "$container" "$command" "$@"
}

# Inspect container
# Args: container_name (string), format (string, optional)
# Returns: inspection output via echo
rhdwp_docker_inspect() {
	local container="$1"
	local format="${2:-}"
	
	if [[ -n "$format" ]]; then
		docker inspect --format="$format" "$container" 2>/dev/null
	else
		docker inspect "$container" 2>/dev/null
	fi
}

# Get container IP address
# Args: container_name (string), network (string, optional)
# Returns: IP address via echo
rhdwp_docker_get_ip() {
	local container="$1"
	local network="${2:-}"
	
	if [[ -n "$network" ]]; then
		docker inspect --format="{{range .NetworkSettings.Networks}}{{if eq .NetworkID \"$(docker network inspect --format='{{.Id}}' "$network" 2>/dev/null)\"}}{{.IPAddress}}{{end}}{{end}}" "$container" 2>/dev/null
	else
		docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container" 2>/dev/null | head -1
	fi
}

# Remove container
# Args: container_name (string), force (boolean, default: false)
# Returns: 0 on success, 1 on failure
rhdwp_docker_rm() {
	local container="$1"
	local force="${2:-false}"
	
	if ! rhdwp_docker_container_exists "$container"; then
		rhdwp_log_debug "Container does not exist: $container"
		return 0
	fi
	
	if [[ "$force" == "true" ]]; then
		rhdwp_log_info "Force removing container: $container"
		rhdwp_run docker rm -f "$container" || return 1
	else
		rhdwp_log_info "Removing container: $container"
		rhdwp_run docker rm "$container" || return 1
	fi
	
	return 0
}

# Get all containers for a project
# Args: project_name (string)
# Returns: container names via echo (one per line)
rhdwp_docker_get_project_containers() {
	local project="$1"
	docker ps -a --filter "label=com.docker.compose.project=$project" --format '{{.Names}}' 2>/dev/null
}

# Check if any containers are running for a project
# Args: project_name (string)
# Returns: 0 if any running, 1 otherwise
rhdwp_docker_project_has_running() {
	local project="$1"
	local count
	count=$(docker ps --filter "label=com.docker.compose.project=$project" --format '{{.Names}}' | wc -l)
	[[ $count -gt 0 ]]
}

# Initialize Docker operations
rhdwp_init_docker() {
	# Check Docker is available
	rhdwp_require_command docker || return 1
	
	# Check Docker is running
	rhdwp_docker_is_running || return 1
	
	# Detect compose command
	_rhdwp_detect_docker_compose || return 1
	
	rhdwp_log_debug "Docker operations initialized"
	return 0
}
