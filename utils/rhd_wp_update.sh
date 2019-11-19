#!/bin/bash

set -e

script_path=$(realpath "$0")
utils_path=$(dirname "${script_path}")
www_path=$(dirname "${utils_path}")/www

for d in "${www_path}"/*; do
	if [ -d "$d" ]; then
		docker_compose="${d}"/docker-compose.yml

		docker-compose -f "${docker_compose}" --log-level ERROR run --rm wp-cli plugin update --all
		docker-compose -f "${docker_compose}" --log-level ERROR run --rm wp-cli theme update --all
		docker-compose -f "${docker_compose}" --log-level ERROR run --rm wp-cli core update
	fi
done