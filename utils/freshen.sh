#!/bin/bash

# set -x

set -e

parent=../

for d in "${parent}"/www/*; do
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