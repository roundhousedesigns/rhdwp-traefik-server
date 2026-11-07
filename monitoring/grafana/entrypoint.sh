#!/bin/bash
# Grafana reads GF_SECURITY_ADMIN_PASSWORD only while creating the admin user.
# After that, traefik/.env can change and the sqlite user keeps the old secret.
# Reset user id 1 from the current env before serving, then align the login
# when the account is still the original admin or GRAFANA_ADMIN_USER.
set -euo pipefail

home_dir="${GF_PATHS_HOME:-/usr/share/grafana}"
config_path="${GF_PATHS_CONFIG:-/etc/grafana/grafana.ini}"
data_dir="${GF_PATHS_DATA:-/var/lib/grafana}"
addr="${GF_SERVER_HTTP_ADDR:-127.0.0.1}"
port="${GF_SERVER_HTTP_PORT:-3000}"
password="${GF_SECURITY_ADMIN_PASSWORD:-}"
desired_user="${GF_SECURITY_ADMIN_USER:-admin}"
db_file="${data_dir}/grafana.db"

if [[ -z "$password" ]]; then
	echo "GF_SECURITY_ADMIN_PASSWORD is empty; not starting Grafana." >&2
	exit 1
fi

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_field() {
	local json=$1 key=$2 line
	line=$(printf '%s' "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p") || return 1
	printf '%s' "${line%%$'\n'*}"
}

basic_auth() {
	printf '%s:%s' "$1" "$2" | base64 | tr -d '\n'
}

reset_admin_password() {
	local output
	output=$(
		printf '%s\n' "$password" | grafana cli \
			--homepath "$home_dir" \
			--config "$config_path" \
			admin reset-admin-password --user-id 1 --password-from-stdin 2>&1
	) || true
	printf '%s\n' "$output"
	if ! printf '%s\n' "$output" | grep -F -q "Admin password changed successfully"; then
		echo "Grafana rejected GRAFANA_ADMIN_PASSWORD. The default policy requires at least 4 characters." >&2
		return 1
	fi
}

auth_header() {
	printf 'Authorization: Basic %s' "$(basic_auth "$1" "$password")"
}

api_get_user() {
	local user=$1
	curl -sS -f -H "$(auth_header "$user")" "http://${addr}:${port}/api/user"
}

sync_admin_login() {
	local auth_user response login email name code
	if response=$(api_get_user "$desired_user" 2>/dev/null); then
		auth_user=$desired_user
	elif [[ "$desired_user" != "admin" ]] && response=$(api_get_user admin 2>/dev/null); then
		auth_user=admin
	else
		echo "Grafana admin password was reset for user id 1, but the login is not ${desired_user}." >&2
		return 0
	fi

	login=$(json_field "$response" login)
	if [[ "$login" == "$desired_user" ]]; then
		return 0
	fi

	email=$(json_field "$response" email)
	name=$(json_field "$response" name)
	if [[ -z "$email" ]]; then
		echo "Could not read the Grafana admin profile to rename ${login} to ${desired_user}." >&2
		return 0
	fi

	code=$(
		curl -sS -o /tmp/grafana-admin-update.json -w '%{http_code}' \
			-X PUT \
			-H 'Content-Type: application/json' \
			-H "$(auth_header "$auth_user")" \
			--data-binary "{\"login\":\"$(json_escape "$desired_user")\",\"email\":\"$(json_escape "$email")\",\"name\":\"$(json_escape "$name")\"}" \
			"http://${addr}:${port}/api/admin/users/1"
	) || return 0
	if [[ "$code" != "200" ]]; then
		echo "Grafana kept admin login ${login}. Renaming it to ${desired_user} returned HTTP ${code}." >&2
		return 0
	fi
	echo "Grafana admin login is now ${desired_user}."
}

wait_for_grafana() {
	local i
	for i in $(seq 1 60); do
		if curl -sf "http://${addr}:${port}/api/health" >/dev/null; then
			return 0
		fi
		if ! kill -0 "$server_pid" 2>/dev/null; then
			wait "$server_pid"
			return $?
		fi
		sleep 1
	done
	echo "Grafana did not become ready; the admin login was not checked." >&2
	return 0
}

if [[ -f "$db_file" ]]; then
	reset_admin_password
	/run.sh "$@" &
	server_pid=$!
	trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' INT TERM
	wait_for_grafana
	sync_admin_login || true
	wait "$server_pid"
else
	exec /run.sh "$@"
fi
