#!/bin/bash

# set -x

set -e

script_path=$(realpath "$0")
utils_path=$(dirname "${script_path}")
www_path=$(dirname "${utils_path}")/www

for d in "${www_path}"/*; do
	dir="${d##*/}"

	echo "UPDATE ${dir}"
	echo "${dir}: Pulling from remote"
	git -C "${d}" pull -q
	
	# Rebuild
	bash "${d}"/build.sh -r

	# shuffle salts (bug in docker wordpress)
	# docker-compose run --rm wp-cli config shuffle-salts

done
docker system prune --volumes -f